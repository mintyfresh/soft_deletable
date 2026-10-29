# frozen_string_literal: true

# == Schema Information
#
# Table name: products
#
#  id             :integer          not null, primary key
#  created_by_id  :integer          not null
#  name           :string           not null
#  price_cents    :integer          not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  deleted_at     :datetime
#  deleted_in     :string
#  deleted_by_id  :integer
#  variants_count :integer          default(0), not null
#
# Indexes
#
#  index_products_on_created_by_id  (created_by_id)
#  index_products_on_deleted_by_id  (deleted_by_id)
#
# Foreign Keys
#
#  created_by_id  (created_by_id => users.id)
#  deleted_by_id  (deleted_by_id => users.id)
#
require 'rails_helper'

RSpec.describe Product, type: :model do
  subject(:product) { build(:product) }

  it { is_expected.to be_valid }

  describe '#destroy' do
    subject(:destroy) { product.destroy }

    let(:product) { create(:product) }

    it 'soft-deletes the product', :aggregate_failures do
      expect(destroy).to be_truthy
      expect(product).to be_deleted.and have_attributes(
        deleted_in: be_present,
        deleted_by: nil
      )
    end

    context 'with a deleted-by user' do
      subject(:destroy) { product.destroy(deleted_by:) }

      let(:deleted_by) { create(:user) }

      it 'sets the deleted-by user', :aggregate_failures do
        expect(destroy).to be_truthy
        expect(product).to be_deleted.and have_attributes(
          deleted_in: be_present,
          deleted_by:
        )
      end
    end

    context 'with a deleted-in value' do
      subject(:destroy) { product.destroy(deleted_in:) }

      let(:deleted_in) { SecureRandom.uuid }

      it 'sets the deleted-in value', :aggregate_failures do
        expect(destroy).to be_truthy
        expect(product).to be_deleted.and have_attributes(
          deleted_in:,
          deleted_by: nil
        )
      end
    end

    context 'with an associated inventory' do
      let(:product) { create(:product, :with_inventory) }

      it 'soft-deletes the inventory', :aggregate_failures do
        expect(destroy).to be_truthy
        expect(product.inventory).to be_deleted.and have_attributes(
          deleted_in: product.deleted_in,
          deleted_by: product.deleted_by
        )
      end
    end

    context 'with an unsaved inventory' do
      let(:product) { create(:product) }
      let!(:inventory) { product.build_inventory(attributes_for(:product_inventory)) }

      it 'soft-deletes the inventory', :aggregate_failures do
        expect(destroy).to be_truthy
        expect(inventory).to be_persisted.and be_deleted.and have_attributes(
          deleted_in: product.deleted_in,
          deleted_by: product.deleted_by
        )
      end
    end

    context 'with associated variants' do
      let(:product) { create(:product, :with_variants) }

      it 'soft-deletes the product', :aggregate_failures do
        expect(destroy).to be_truthy
        expect(product).to be_deleted.and have_attributes(
          deleted_in: be_present,
          deleted_by: nil
        )
      end

      it 'soft-deletes all the variants', :aggregate_failures do
        expect(destroy).to be_truthy
        expect(product.variants).to all be_deleted.and have_attributes(
          deleted_in: product.deleted_in,
          deleted_by: product.deleted_by
        )
      end

      context 'with a deleted-by user' do
        subject(:destroy) { product.destroy(deleted_by:) }

        let(:deleted_by) { create(:user) }

        it 'sets the deleted-by user', :aggregate_failures do
          expect(destroy).to be_truthy
          expect(product).to be_deleted.and have_attributes(
            deleted_in: be_present,
            deleted_by:
          )
        end

        it 'sets the deleted-by user for the variants', :aggregate_failures do
          expect(destroy).to be_truthy
          expect(product.variants).to all be_deleted.and have_attributes(
            deleted_in: product.deleted_in,
            deleted_by: product.deleted_by
          )
        end
      end
    end

    context 'with a mix of saved and unsaved variants' do
      let(:product) { create(:product, :with_variants) }
      let!(:saved_variants) { product.variants.to_a }
      let!(:unsaved_variant) { product.variants.build(attributes_for(:product_variant)) }

      it 'soft-deletes the saved variants', :aggregate_failures do
        expect(destroy).to be_truthy
        expect(saved_variants).to all be_deleted.and have_attributes(
          deleted_in: product.deleted_in,
          deleted_by: product.deleted_by
        )
      end

      it 'soft-deletes the unsaved variant', :aggregate_failures do
        expect(destroy).to be_truthy
        expect(unsaved_variant).to be_persisted.and be_deleted.and have_attributes(
          deleted_in: product.deleted_in,
          deleted_by: product.deleted_by
        )
      end
    end

    context 'when permanent' do
      subject(:destroy) { product.destroy(permanent: true) }

      it 'hard-deletes the product', :aggregate_failures do
        expect(destroy).to be_truthy
        expect(product).to be_destroyed
        expect(described_class.exists?(product.id)).to be(false)
      end

      context 'when the product is already soft-deleted' do
        let(:product) { create(:product, :deleted) }

        it 'hard-deletes the product' do
          expect { destroy }.to change { described_class.exists?(product.id) }.from(true).to(false)
        end
      end

      context 'with associated variants' do
        let(:product) { create(:product, :with_variants) }
        let!(:previously_deleted_variant) { create(:product_variant, :deleted, product:) }

        it 'hard-deletes all the variants, including previously soft-deleted ones', :aggregate_failures do
          expect(destroy).to be_truthy
          expect(ProductVariant.where(product_id: product.id)).to be_empty
          expect(ProductVariant.exists?(previously_deleted_variant.id)).to be(false)
        end
      end

      context 'with a previously soft-deleted inventory' do
        let(:product) { create(:product) }
        let!(:inventory) { create(:product_inventory, :deleted, product:) }

        it 'hard-deletes the inventory', :aggregate_failures do
          expect(destroy).to be_truthy
          expect(ProductInventory.exists?(inventory.id)).to be(false)
        end
      end
    end
  end

  describe '#destroy!' do
    context 'when permanent' do
      subject(:destroy!) { product.destroy!(permanent: true) }

      let(:product) { create(:product, :with_variants, :with_inventory) }

      it 'hard-deletes the product and its dependents', :aggregate_failures do
        expect(destroy!).to be_truthy
        expect(described_class.exists?(product.id)).to be(false)
        expect(ProductVariant.where(product_id: product.id)).to be_empty
        expect(ProductInventory.where(product_id: product.id)).to be_empty
      end
    end
  end

  describe '#delete' do
    context 'when permanent' do
      subject(:delete) { product.delete(permanent: true) }

      let(:product) { create(:product) }

      it 'hard-deletes the product', :aggregate_failures do
        expect(delete).to be_truthy
        expect(product).to be_destroyed
        expect(described_class.exists?(product.id)).to be(false)
      end
    end
  end

  describe 'permanent deletion with other dependent options' do
    let(:product) { create(:product, :with_variants, :with_inventory) }
    let!(:previously_deleted_variant) { create(:product_variant, :deleted, product:) }

    before(:each) do
      stub_const('DeletingProduct', Class.new(ApplicationRecord) do
        self.table_name = 'products'
        include SoftDeletable::Model

        has_many :variants, class_name: 'ProductVariant', foreign_key: :product_id,
                            inverse_of: false, dependent: :delete_all
        has_one :inventory, class_name: 'ProductInventory', foreign_key: :product_id,
                            inverse_of: false, dependent: :delete
      end)
    end

    it 'hard-deletes has_many :delete_all and has_one :delete dependents', :aggregate_failures do
      expect(DeletingProduct.find(product.id).destroy(permanent: true)).to be_truthy
      expect(ProductVariant.where(product_id: product.id)).to be_empty
      expect(ProductVariant.exists?(previously_deleted_variant.id)).to be(false)
      expect(ProductInventory.where(product_id: product.id)).to be_empty
    end
  end

  describe 'permanent deletion of an owner that is not soft-deletable' do
    let(:product) { create(:product, :with_variants, :with_inventory) }

    before(:each) do
      stub_const('PlainProductWithVariants', Class.new(ApplicationRecord) do
        self.table_name = 'products'

        has_many :variants, class_name: 'ProductVariant', foreign_key: :product_id,
                            inverse_of: false, dependent: :destroy
      end)

      stub_const('PlainProductWithInventory', Class.new(ApplicationRecord) do
        self.table_name = 'products'

        has_one :inventory, class_name: 'ProductInventory', foreign_key: :product_id,
                            inverse_of: false, dependent: :destroy
      end)
    end

    %w[PlainProductWithVariants PlainProductWithInventory].each do |class_name|
      it "refuses to cascade to soft-deletable dependents of #{class_name}", :aggregate_failures do
        owner = class_name.constantize.find(product.id)

        expect { owner.destroy }.to raise_error(SoftDeletable::PermanentCascadeError)
        expect(described_class.exists?(product.id)).to be(true)
        expect(product.variants.reload).to all have_attributes(deleted?: false)
        expect(product.inventory.reload).to have_attributes(deleted?: false)
      end
    end
  end

  describe 'soft-deletion with restricted dependents' do
    let(:product) { create(:product) }
    let(:exception_restricting_product) { ExceptionRestrictingProduct.find(product.id) }
    let(:error_restricting_product) { ErrorRestrictingProduct.find(product.id) }

    before(:each) do
      stub_const('ExceptionRestrictingProduct', Class.new(ApplicationRecord) do
        self.table_name = 'products'
        include SoftDeletable::Model

        has_many :variants, class_name: 'ProductVariant', foreign_key: :product_id,
                            inverse_of: false, dependent: :restrict_with_exception
        has_one :inventory, class_name: 'ProductInventory', foreign_key: :product_id,
                            inverse_of: false, dependent: :restrict_with_exception
      end)

      stub_const('ErrorRestrictingProduct', Class.new(ApplicationRecord) do
        self.table_name = 'products'
        include SoftDeletable::Model

        has_many :variants, class_name: 'ProductVariant', foreign_key: :product_id,
                            inverse_of: false, dependent: :restrict_with_error
        has_one :inventory, class_name: 'ProductInventory', foreign_key: :product_id,
                            inverse_of: false, dependent: :restrict_with_error
      end)
    end

    context 'with a non-deleted variant' do
      let!(:variant) { create(:product_variant, product:) }

      it 'raises when restricted with an exception', :aggregate_failures do
        expect { exception_restricting_product.destroy }.to raise_error(ActiveRecord::DeleteRestrictionError)
        expect(exception_restricting_product).not_to be_deleted
        expect(product.reload).not_to be_deleted
        expect(variant.reload).not_to be_deleted
      end

      it 'adds an error when restricted with an error', :aggregate_failures do
        expect(error_restricting_product.destroy).to be(false)
        expect(error_restricting_product).not_to be_deleted
        expect(error_restricting_product.errors.full_messages).to eq(
          ['Cannot delete record because dependent variants exist']
        )
        expect(product.reload).not_to be_deleted
        expect(variant.reload).not_to be_deleted
      end

      it 'raises from destroy! when restricted with an error', :aggregate_failures do
        expect { error_restricting_product.destroy! }.to raise_error(ActiveRecord::RecordNotDestroyed)
        expect(error_restricting_product).not_to be_deleted
        expect(product.reload).not_to be_deleted
      end

      it 'raises when permanently deleted', :aggregate_failures do
        expect { exception_restricting_product.destroy(permanent: true) }
          .to raise_error(ActiveRecord::DeleteRestrictionError)
        expect(described_class.exists?(product.id)).to be(true)
      end
    end

    context 'with a previously deleted variant' do
      let!(:previously_deleted_variant) { create(:product_variant, :deleted, product:) }

      it 'soft-deletes the product when restricted with an exception', :aggregate_failures do
        expect(exception_restricting_product.destroy).to be_truthy
        expect(product.reload).to be_deleted
        expect { previously_deleted_variant.reload }.not_to(change { previously_deleted_variant.attributes })
      end

      it 'soft-deletes the product when restricted with an error', :aggregate_failures do
        expect(error_restricting_product.destroy).to be_truthy
        expect(product.reload).to be_deleted
        expect { previously_deleted_variant.reload }.not_to(change { previously_deleted_variant.attributes })
      end
    end

    context 'with a non-deleted inventory' do
      let!(:inventory) { create(:product_inventory, product:) }

      it 'raises when restricted with an exception', :aggregate_failures do
        expect { exception_restricting_product.destroy }.to raise_error(ActiveRecord::DeleteRestrictionError)
        expect(exception_restricting_product).not_to be_deleted
        expect(product.reload).not_to be_deleted
        expect(inventory.reload).not_to be_deleted
      end

      it 'adds an error when restricted with an error', :aggregate_failures do
        expect(error_restricting_product.destroy).to be(false)
        expect(error_restricting_product).not_to be_deleted
        expect(error_restricting_product.errors.full_messages).to eq(
          ['Cannot delete record because a dependent inventory exists']
        )
        expect(product.reload).not_to be_deleted
        expect(inventory.reload).not_to be_deleted
      end
    end

    context 'with a previously deleted inventory' do
      let!(:previously_deleted_inventory) { create(:product_inventory, :deleted, product:) }

      it 'soft-deletes the product without changing the inventory', :aggregate_failures do
        expect(exception_restricting_product.destroy).to be_truthy
        expect(product.reload).to be_deleted
        expect { previously_deleted_inventory.reload }.not_to(change { previously_deleted_inventory.attributes })
      end
    end

    context 'when skipping the restriction on soft-delete' do
      let!(:variant) { create(:product_variant, product:) }
      let!(:inventory) { create(:product_inventory, product:) }
      let(:skipping_product) { SkippingProduct.find(product.id) }

      before(:each) do
        stub_const('SkippingProduct', Class.new(ApplicationRecord) do
          self.table_name = 'products'
          include SoftDeletable::Model

          with_options foreign_key: :product_id, inverse_of: false, skip_restriction_on_soft_delete: true do
            has_many :variants, class_name: 'ProductVariant', dependent: :restrict_with_exception
            has_one :inventory, class_name: 'ProductInventory', dependent: :restrict_with_error
          end
        end)
      end

      it 'soft-deletes the product without changing its dependents', :aggregate_failures do
        expect(skipping_product.destroy).to be_truthy
        expect(product.reload).to be_deleted
        expect(variant.reload).not_to be_deleted
        expect(inventory.reload).not_to be_deleted
      end

      it 'still raises when permanently deleted', :aggregate_failures do
        expect { skipping_product.destroy(permanent: true) }.to raise_error(ActiveRecord::DeleteRestrictionError)
        expect(described_class.exists?(product.id)).to be(true)
      end
    end

    context 'when skipping the restriction on soft-delete by default' do
      let!(:variant) { create(:product_variant, product:) }

      before(:each) do
        allow(SoftDeletable).to receive(:config)
          .and_return(SoftDeletable.config.dup.tap { |config| config.skip_restriction_on_soft_delete = true })

        stub_const('EnforcingProduct', Class.new(ApplicationRecord) do
          self.table_name = 'products'
          include SoftDeletable::Model

          has_many :variants, class_name: 'ProductVariant', foreign_key: :product_id,
                              inverse_of: false, dependent: :restrict_with_exception,
                              skip_restriction_on_soft_delete: false
        end)
      end

      it 'soft-deletes the product without changing its variants', :aggregate_failures do
        expect(exception_restricting_product.destroy).to be_truthy
        expect(product.reload).to be_deleted
        expect(variant.reload).not_to be_deleted
      end

      it 'raises when the association overrides the default', :aggregate_failures do
        expect { EnforcingProduct.find(product.id).destroy }.to raise_error(ActiveRecord::DeleteRestrictionError)
        expect(product.reload).not_to be_deleted
      end
    end

    it 'rejects skipping the restriction on soft-delete for associations that do not restrict deletion' do
      expect do
        Class.new(ApplicationRecord) do
          self.table_name = 'products'

          has_many :variants, class_name: 'ProductVariant', foreign_key: :product_id,
                              inverse_of: false, dependent: :destroy, skip_restriction_on_soft_delete: true
        end
      end.to raise_error(ArgumentError, /cannot use skip_restriction_on_soft_delete/)
    end
  end

  describe '#mark_for_destruction' do
    let(:product) { create(:product, :with_variants, :with_inventory) }
    let(:autosaving_product) { AutosavingProduct.find(product.id) }

    before(:each) do
      stub_const('AutosavingProduct', Class.new(ApplicationRecord) do
        self.table_name = 'products'
        include SoftDeletable::Model

        has_many :variants, class_name: 'ProductVariant', foreign_key: :product_id,
                            inverse_of: false, dependent: :destroy, autosave: true
        has_one :inventory, class_name: 'ProductInventory', foreign_key: :product_id,
                            inverse_of: false, dependent: :destroy, autosave: true
      end)
    end

    it 'soft-deletes a marked variant when the owner is saved', :aggregate_failures do
      variant = autosaving_product.variants.load.first
      variant.mark_for_destruction
      autosaving_product.save!

      expect(variant).not_to be_marked_for_destruction
      expect(variant.reload).to be_deleted
    end

    context 'when permanent' do
      it 'marks the record for destruction' do
        variant = product.variants.first
        expect { variant.mark_for_destruction(permanent: true) }
          .to change { variant.marked_for_destruction? }.from(false).to(true)
      end

      it 'marks an already soft-deleted record for destruction' do
        variant = create(:product_variant, :deleted, product:)
        expect { variant.mark_for_destruction(permanent: true) }
          .to change { variant.marked_for_destruction? }.from(false).to(true)
      end

      it 'hard-deletes a marked variant when the owner is saved', :aggregate_failures do
        variant = autosaving_product.variants.load.first
        variant.mark_for_destruction(permanent: true)
        autosaving_product.save!

        expect(ProductVariant.exists?(variant.id)).to be(false)
        expect(autosaving_product.variants.reload.size).to eq(2)
      end

      it 'hard-deletes a marked inventory when the owner is saved' do
        inventory = autosaving_product.inventory
        inventory.mark_for_destruction(permanent: true)
        autosaving_product.save!

        expect(ProductInventory.exists?(inventory.id)).to be(false)
      end
    end
  end

  describe '.delete_all' do
    let!(:products) { create_list(:product, 3) }
    let!(:previously_deleted_product) { create(:product, :deleted) }

    it 'soft-deletes the non-deleted records in a single operation', :aggregate_failures do
      expect(described_class.delete_all).to eq(3)
      expect(products.map(&:reload)).to all be_deleted
      expect(products.map(&:deleted_in).uniq).to contain_exactly(be_present)
    end

    it 'leaves previously soft-deleted records untouched' do
      expect { described_class.delete_all }.not_to(change { previously_deleted_product.reload.attributes })
    end

    it 'only soft-deletes records within the scope', :aggregate_failures do
      described_class.where(id: products.first).delete_all
      expect(products.first.reload).to be_deleted
      expect(products.drop(1).map(&:reload)).to all have_attributes(deleted?: false)
    end

    it 'sets the deleted-by user and deleted-in value' do
      deleted_by = create(:user)
      deleted_in = SecureRandom.uuid
      described_class.where(id: products.first).delete_all(deleted_by:, deleted_in:)
      expect(products.first.reload).to have_attributes(deleted_by:, deleted_in:)
    end

    context 'when permanent' do
      it 'hard-deletes all records in the scope, including soft-deleted ones', :aggregate_failures do
        expect(described_class.delete_all(permanent: true)).to eq(4)
        expect(described_class.count).to eq(0)
      end
    end
  end

  describe '#variants.delete_all' do
    let(:product) { create(:product, :with_variants) }
    let!(:previously_deleted_variant) { create(:product_variant, :deleted, product:) }
    let!(:variants) { product.variants.reload.to_a }

    it 'soft-deletes the variants in the collection', :aggregate_failures do
      expect(product.variants.delete_all).to eq(3)
      expect(variants.map(&:reload)).to all be_deleted
      expect(product.variants.reload).to be_empty
    end

    it 'sets the deleted-by user and deleted-in value' do
      deleted_by = create(:user)
      deleted_in = SecureRandom.uuid
      product.variants.delete_all(deleted_by:, deleted_in:)
      expect(variants.map(&:reload)).to all have_attributes(deleted_by:, deleted_in:)
    end

    context 'when permanent' do
      it 'hard-deletes the variants in the collection', :aggregate_failures do
        expect(product.variants.delete_all(permanent: true)).to eq(3)
        expect(ProductVariant.where(id: variants)).to be_empty
        expect(product.variants.reload).to be_empty
      end

      it 'leaves variants outside of the collection untouched' do
        product.variants.delete_all(permanent: true)
        expect(ProductVariant.exists?(previously_deleted_variant.id)).to be(true)
      end
    end

    context 'when nullifying' do
      it 'rejects deletion options' do
        expect { product.variants.delete_all(:nullify, permanent: true) }
          .to raise_error(ArgumentError, /does not support deletion options/)
      end
    end
  end

  describe '.destroy_all' do
    let!(:products) { create_list(:product, 3, :with_variants) }
    let!(:previously_deleted_product) { create(:product, :deleted) }

    it 'soft-deletes the non-deleted records and their dependents in a single operation', :aggregate_failures do
      described_class.destroy_all
      expect(products.map(&:reload)).to all be_deleted
      expect(products.map(&:deleted_in).uniq).to contain_exactly(be_present)
      expect(ProductVariant.where(product: products).distinct.pluck(:deleted_in)).to eq([products.first.deleted_in])
    end

    it 'leaves previously soft-deleted records untouched' do
      expect { described_class.destroy_all }.not_to(change { previously_deleted_product.reload.attributes })
    end

    it 'sets the deleted-by user and deleted-in value' do
      deleted_by = create(:user)
      deleted_in = SecureRandom.uuid
      described_class.where(id: products).destroy_all(deleted_by:, deleted_in:)
      expect(products.map(&:reload)).to all have_attributes(deleted_by:, deleted_in:)
    end

    context 'when permanent' do
      it 'hard-deletes all records in the scope and their dependents, including deleted ones', :aggregate_failures do
        described_class.destroy_all(permanent: true)
        expect(described_class.count).to eq(0)
        expect(ProductVariant.count).to eq(0)
      end
    end
  end

  describe '#variants.destroy_all' do
    let(:product) { create(:product, :with_variants) }
    let!(:previously_deleted_variant) { create(:product_variant, :deleted, product:) }
    let!(:variants) { product.variants.reload.to_a }

    it 'soft-deletes the variants in the collection in a single operation', :aggregate_failures do
      product.variants.destroy_all
      expect(variants.map(&:reload)).to all be_deleted
      expect(variants.map(&:deleted_in).uniq).to contain_exactly(be_present)
      expect(product.variants.reload).to be_empty
    end

    it 'decrements the counter cache' do
      expect { product.variants.destroy_all }.to change { product.reload.variants_count }.from(3).to(0)
    end

    it 'sets the deleted-by user and deleted-in value' do
      deleted_by = create(:user)
      deleted_in = SecureRandom.uuid
      product.variants.destroy_all(deleted_by:, deleted_in:)
      expect(variants.map(&:reload)).to all have_attributes(deleted_by:, deleted_in:)
    end

    context 'when permanent' do
      it 'hard-deletes the variants in the collection', :aggregate_failures do
        product.variants.destroy_all(permanent: true)
        expect(ProductVariant.where(id: variants)).to be_empty
        expect(product.variants.reload).to be_empty
      end

      it 'leaves variants outside of the collection untouched' do
        product.variants.destroy_all(permanent: true)
        expect(ProductVariant.exists?(previously_deleted_variant.id)).to be(true)
      end
    end
  end

  describe '.restore_all' do
    let!(:deleted_product) { create(:product, :with_variants).tap(&:destroy!) }
    let!(:other_deleted_product) { create(:product).tap(&:destroy!) }
    let!(:non_deleted_product) { create(:product) }

    it 'restores the deleted records and returns them', :aggregate_failures do
      expect(described_class.restore_all).to contain_exactly(deleted_product, other_deleted_product)
      expect([deleted_product, other_deleted_product].map(&:reload)).to all have_attributes(deleted: false)
    end

    it 'cascades the restoration to their dependents' do
      described_class.restore_all
      expect(ProductVariant.where(product: deleted_product)).to contain_exactly(
        have_attributes(deleted: false), have_attributes(deleted: false), have_attributes(deleted: false)
      )
    end

    it 'leaves non-deleted records untouched' do
      expect { described_class.restore_all }.not_to(change { non_deleted_product.reload.attributes })
    end

    it 'only restores the records in the relation', :aggregate_failures do
      expect(described_class.where(id: deleted_product).restore_all).to contain_exactly(deleted_product)
      expect(other_deleted_product.reload).to be_deleted
    end
  end

  describe '.restore_by' do
    let!(:deleted_product) { create(:product).tap(&:destroy!) }
    let!(:other_deleted_product) { create(:product).tap(&:destroy!) }

    it 'restores the deleted records matching the conditions', :aggregate_failures do
      expect(described_class.restore_by(id: deleted_product.id)).to contain_exactly(deleted_product)
      expect(deleted_product.reload).not_to be_deleted
      expect(other_deleted_product.reload).to be_deleted
    end
  end

  describe '.undelete_all' do
    let!(:deleted_product) { create(:product, :with_variants).tap(&:destroy!) }
    let!(:other_deleted_product) { create(:product).tap(&:destroy!) }
    let!(:non_deleted_product) { create(:product) }

    it 'restores the deleted records and returns their count', :aggregate_failures do
      expect(described_class.undelete_all).to eq(2)
      expect([deleted_product, other_deleted_product].map(&:reload)).to all have_attributes(deleted: false)
    end

    it 'does not cascade the restoration to their dependents' do
      described_class.undelete_all
      expect(ProductVariant.where(product: deleted_product)).to be_present.and all have_attributes(deleted: true)
    end

    it 'leaves non-deleted records untouched' do
      expect { described_class.undelete_all }.not_to(change { non_deleted_product.reload.attributes })
    end

    it 'only restores the records in the relation', :aggregate_failures do
      expect(described_class.where(id: deleted_product).undelete_all).to eq(1)
      expect(other_deleted_product.reload).to be_deleted
    end
  end

  describe '#variants.restore_all' do
    let!(:product) { create(:product) }
    let!(:deleted_variant) { create(:product_variant, :deleted, product:) }

    it 'does not restore variants hidden by the collection' do
      expect(product.variants.restore_all).to be_empty
    end

    it 'restores the deleted variants when the collection includes them', :aggregate_failures do
      expect(product.all_variants.restore_all).to contain_exactly(deleted_variant)
      expect(deleted_variant.reload).not_to be_deleted
      expect(product.variants.reload).to contain_exactly(deleted_variant)
    end

    it 'restores the deleted variants when the collection is unscoped from its deleted state', :aggregate_failures do
      expect(product.variants.unscope_deleted.restore_all).to contain_exactly(deleted_variant)
      expect(deleted_variant.reload).not_to be_deleted
      expect(product.variants.reload).to contain_exactly(deleted_variant)
    end

    it 'restores the deleted variants when the collection is rescoped to deleted variants', :aggregate_failures do
      expect(product.variants.unscope_deleted.deleted.restore_all).to contain_exactly(deleted_variant)
      expect(deleted_variant.reload).not_to be_deleted
      expect(product.variants.reload).to contain_exactly(deleted_variant)
    end

    context 'when the product is deleted' do
      let!(:variant_deleted_together) { create(:product_variant, product:) }

      before(:each) do
        product.destroy!
      end

      it 'restores the variants deleted separately and together when the collection is unscoped', :aggregate_failures do
        expect(product.variants.unscope_deleted.restore_all)
          .to contain_exactly(deleted_variant, variant_deleted_together)
        expect([deleted_variant, variant_deleted_together].map(&:reload)).to all have_attributes(deleted: false)
        expect(product.reload).to be_deleted
      end

      it 'restores the variants deleted separately and together when the collection is rescoped' do
        expect(product.variants.unscope_deleted.deleted.restore_all)
          .to contain_exactly(deleted_variant, variant_deleted_together)
      end
    end
  end

  describe '#variants.undelete_all' do
    let!(:product) { create(:product) }
    let!(:deleted_variant) { create(:product_variant, :deleted, product:) }

    it 'restores the deleted variants when the collection is unscoped from its deleted state', :aggregate_failures do
      expect(product.variants.unscope_deleted.undelete_all).to eq(1)
      expect(deleted_variant.reload).not_to be_deleted
    end
  end

  describe 'restoring a relation of a model that is not soft-deletable' do
    let!(:plain_product_class) do
      stub_const('PlainProduct', Class.new(ApplicationRecord) { self.table_name = 'products' })
    end

    it 'rejects the restoration', :aggregate_failures do
      expect { plain_product_class.all.restore_all }.to raise_error(NoMethodError, /not soft-deletable/)
      expect { plain_product_class.all.undelete_all }.to raise_error(NoMethodError, /not soft-deletable/)
      expect { plain_product_class.all.restore_by(id: 1) }.to raise_error(NoMethodError, /not soft-deletable/)
    end
  end

  describe '#save' do
    subject(:save) { product.save }

    context 'when the record is created in a deleted state' do
      let(:product) { build(:product, :deleted, :with_inventory, :with_variants) }

      it 'soft-deletes the inventory', :aggregate_failures do
        expect(save).to be_truthy
        expect(product.inventory).to be_persisted.and be_deleted.and have_attributes(
          deleted_in: product.deleted_in,
          deleted_by: product.deleted_by
        )
      end

      it 'soft-deletes all the variants', :aggregate_failures do
        expect(save).to be_truthy
        expect(product.variants).to all be_persisted.and be_deleted.and have_attributes(
          deleted_in: product.deleted_in,
          deleted_by: product.deleted_by
        )
      end
    end

    context 'when the record is created in a deleted state with an already-saved inventory' do
      let(:product) { build(:product, :deleted) }
      let(:inventory) { create(:product_inventory) }

      before(:each) do
        product.inventory = inventory
      end

      it 'soft-deletes the inventory', :aggregate_failures do
        expect(save).to be_truthy
        expect(inventory).to be_deleted.and have_attributes(
          product:,
          deleted_in: product.deleted_in,
          deleted_by: product.deleted_by
        )
      end
    end

    context 'when the record is created in a deleted state with already-saved variants' do
      let(:product) { build(:product, :deleted) }
      let(:variants) { create_list(:product_variant, 2) }

      before(:each) do
        product.variants = variants
      end

      it 'soft-deletes all the variants', :aggregate_failures do
        expect(save).to be_truthy
        expect(variants).to all be_deleted.and have_attributes(
          product:,
          deleted_in: product.deleted_in,
          deleted_by: product.deleted_by
        )
      end
    end

    context 'when an existing record is marked as deleted' do
      let(:product) { described_class.find(inventory.product_id).tap { |product| product.deleted = true } }
      let!(:inventory) { create(:product_inventory) }
      let!(:variants) { create_list(:product_variant, 2, product: inventory.product) }

      it 'reads the non-deleted inventory before saving' do
        expect(product.inventory).to eq(inventory)
      end

      it 'reads the non-deleted variants before saving', :aggregate_failures do
        expect(product.variants).to match_array(variants)
        expect(product.variants.count).to eq(2)
      end

      it 'preloads the non-deleted variants before saving' do
        ActiveRecord::Associations::Preloader.new(records: [product], associations: :variants).call
        expect(product.variants).to match_array(variants)
      end

      it 'soft-deletes the inventory read before saving', :aggregate_failures do
        product.inventory
        expect(save).to be_truthy
        expect(inventory.reload).to be_deleted.and have_attributes(deleted_in: product.deleted_in)
      end

      it 'soft-deletes the variants read before saving', :aggregate_failures do
        product.variants.load
        expect(save).to be_truthy
        expect(variants.map(&:reload)).to all be_deleted.and have_attributes(deleted_in: product.deleted_in)
      end
    end
  end

  describe '#restore' do
    subject(:restore) { product.restore }

    let(:product) { create(:product, :deleted) }

    it 'restores the product', :aggregate_failures do
      expect(restore).to be_truthy
      expect(product).not_to be_deleted
    end

    context 'with associated variants' do
      let(:product) { create(:product, :deleted, :with_variants) }

      it 'restores the product', :aggregate_failures do
        expect(restore).to be_truthy
        expect(product).not_to be_deleted
      end

      it 'restores all the variants', :aggregate_failures do
        expect(restore).to be_truthy
        expect(product.variants).to all have_attributes(deleted: false)
      end

      it "doesn't restore variants that were deleted in a different transaction", :aggregate_failures do
        other_variant = create(:product_variant, :deleted, product:, deleted_in: SecureRandom.uuid)
        expect(restore).to be_truthy
        expect(other_variant.reload).to be_deleted
        expect(product.variants.excluding(other_variant)).to all have_attributes(deleted: false)
      end
    end

    context 'with an associated inventory' do
      let(:product) { create(:product, :deleted, :with_inventory) }

      it 'restores the inventory', :aggregate_failures do
        expect(restore).to be_truthy
        expect(product.inventory).to have_attributes(deleted: false)
      end
    end

    context 'with an unsaved deleted inventory' do
      let(:product) { create(:product, :deleted) }
      let!(:inventory) do
        product.build_inventory(
          attributes_for(:product_inventory).merge(deleted_at: product.deleted_at, deleted_in: product.deleted_in)
        )
      end

      it 'restores the inventory', :aggregate_failures do
        expect(restore).to be_truthy
        expect(inventory).to be_persisted.and have_attributes(deleted: false)
      end

      context 'when it was deleted in a different transaction' do
        let!(:inventory) do
          product.build_inventory(
            attributes_for(:product_inventory).merge(deleted_at: Time.current, deleted_in: SecureRandom.uuid)
          )
        end

        it "doesn't restore the inventory", :aggregate_failures do
          expect(restore).to be_truthy
          expect(inventory).to be_deleted
        end
      end
    end

    context 'with unsaved deleted variants' do
      let(:product) { create(:product, :deleted) }
      let!(:variants) do
        product.variants.build(
          attributes_for_list(:product_variant, 2).map do |attributes|
            attributes.merge(deleted_at: product.deleted_at, deleted_in: product.deleted_in)
          end
        )
      end

      it 'restores all the variants', :aggregate_failures do
        expect(restore).to be_truthy
        expect(variants.map(&:reload)).to all have_attributes(deleted: false)
      end

      context 'when they were deleted in a different transaction' do
        let!(:variants) do
          product.variants.build(
            attributes_for_list(:product_variant, 2).map do |attributes|
              attributes.merge(deleted_at: Time.current, deleted_in: SecureRandom.uuid)
            end
          )
        end

        it "doesn't restore the variants", :aggregate_failures do
          expect(restore).to be_truthy
          expect(variants.map(&:reload)).to all be_deleted
        end
      end
    end
  end

  describe 'association filtering' do
    let(:product) { create(:product, :with_inventory, :with_variants) }
    let!(:previously_deleted_variant) { create(:product_variant, :deleted, product:) }

    context 'when the product is not deleted' do
      it 'only includes variants that are not deleted', :aggregate_failures do
        expect(product.reload.variants).to match_array(ProductVariant.where(product:).not_deleted)
        expect(product.variants).not_to include(previously_deleted_variant)
      end

      it 'includes the inventory' do
        expect(product.reload.inventory).to be_present.and have_attributes(deleted: false)
      end

      it 'is included by its variants' do
        expect(product.variants.first.reload.product).to eq(product)
      end

      it 'is included by its deleted variants' do
        expect(previously_deleted_variant.reload.product).to eq(product)
      end

      it 'is joined from its deleted variants' do
        expect(ProductVariant.joins(:product).where(id: previously_deleted_variant)).to be_present
      end

      it 'is preloaded for its deleted variants' do
        expect(ProductVariant.preload(:product).find(previously_deleted_variant.id).product).to eq(product)
      end

      it 'is only joined to variants that are not deleted' do
        expect(described_class.joins(:variants).where(variants: { id: previously_deleted_variant })).to be_empty
      end

      it 'allows a variant to be deleted on its own', :aggregate_failures do
        variant = product.variants.first.reload
        expect(variant.destroy).to be_truthy
        expect(variant).to be_deleted
        expect(product.reload.variants).not_to include(variant)
      end
    end

    context 'when the product is deleted' do
      before(:each) do
        product.destroy!
        product.reload
      end

      it 'only includes variants deleted in the same operation', :aggregate_failures do
        expect(product.variants).to be_present.and all have_attributes(deleted: true, deleted_in: product.deleted_in)
        expect(product.variants).not_to include(previously_deleted_variant)
      end

      it 'counts variants deleted in the same operation, rather than reading the counter cache', :aggregate_failures do
        expect(product.variants_count).to eq(0)
        expect(product.variants.size).to eq(3)
      end

      it 'includes the inventory deleted in the same operation' do
        expect(product.inventory).to have_attributes(deleted: true, deleted_in: product.deleted_in)
      end

      it 'is included by variants deleted in the same operation' do
        expect(product.variants.first.reload.product).to eq(product)
      end

      it 'is not included by variants deleted in a different operation' do
        expect(previously_deleted_variant.reload.product).to be_nil
      end

      it 'is only joined to variants deleted in the same operation' do
        expect(described_class.joins(:variants).distinct.pluck('product_variants.deleted_in'))
          .to eq([product.deleted_in])
      end
    end

    context 'when preloading for deleted and non-deleted products' do
      let!(:deleted_product) { create(:product, :with_inventory, :with_variants).tap(&:destroy!) }
      let!(:non_deleted_variant) { create(:product_variant, product: deleted_product) }

      %i[preload eager_load].each do |method|
        context "with #{method}" do
          let(:products) do
            described_class.public_send(method, :variants, :inventory)
              .where(id: [product, deleted_product]).index_by(&:id)
          end

          it 'filters the associations of the product that is not deleted', :aggregate_failures do
            expect(products[product.id].variants).to match_array(ProductVariant.where(product:).not_deleted)
            expect(products[product.id].inventory).to have_attributes(deleted: false)
          end

          it 'filters the associations of the deleted product', :aggregate_failures do
            expect(products[deleted_product.id].variants).to be_present.and all have_attributes(
              deleted: true, deleted_in: deleted_product.deleted_in
            )
            expect(products[deleted_product.id].variants).not_to include(non_deleted_variant)
            expect(products[deleted_product.id].inventory).to have_attributes(deleted_in: deleted_product.deleted_in)
          end
        end
      end
    end

    context 'with a belongs_to association, which includes deleted records by default' do
      before(:each) do
        product.destroy!
      end

      it 'is included by an inventory deleted in the same operation' do
        expect(ProductInventory.find_by(product:).product).to eq(product)
      end

      it 'is included by an inventory that is not deleted', :aggregate_failures do
        inventory = ProductInventory.find_by(product:).tap(&:undelete)
        expect(inventory.reload.product).to eq(product)
        expect(ProductInventory.joins(:product).where(id: inventory)).to be_present
      end
    end

    context 'with an association that always includes deleted records' do
      it 'includes all the variants' do
        expect(product.all_variants).to match_array(ProductVariant.where(product:))
      end
    end

    context 'with an association that never includes deleted records' do
      before(:each) do
        product.destroy!
        product.reload
      end

      it 'only includes variants that are not deleted, even though the product is deleted', :aggregate_failures do
        non_deleted_variant = create(:product_variant, product:)
        expect(product.non_deleted_variants).to contain_exactly(non_deleted_variant)
        expect(described_class.preload(:non_deleted_variants).find(product.id).non_deleted_variants)
          .to contain_exactly(non_deleted_variant)
        expect(described_class.joins(:non_deleted_variants).where(id: product).pluck('product_variants.id'))
          .to contain_exactly(non_deleted_variant.id)
      end
    end

    context 'with an unknown includes_deleted option' do
      it 'is not allowed' do
        expect { described_class.has_many :other_variants, class_name: 'ProductVariant', includes_deleted: true }
          .to raise_error(ArgumentError, /Unknown includes_deleted option true/)
      end
    end

    context 'with a deleted-by user' do
      let(:deleted_by) { create(:user) }

      it 'includes the user, who is not deleted' do
        product.destroy!(deleted_by:)
        expect(product.reload.deleted_by).to eq(deleted_by)
      end
    end
  end

  describe 'has_and_belongs_to_many association filtering' do
    let(:product) { create(:product) }
    let(:non_deleted_tag) { create(:tag) }
    let(:previously_deleted_tag) { create(:tag, :deleted) }
    let(:tags) { [non_deleted_tag, previously_deleted_tag] }

    before(:each) do
      product.tags << tags
    end

    shared_examples 'filters the tags' do
      it 'loads the tags from the product' do
        expect(described_class.find(product.id).tags).to match_array(expected_tags)
      end

      %i[preload eager_load].each do |method|
        it "loads the tags with #{method}" do
          expect(described_class.public_send(method, :tags).find(product.id).tags).to match_array(expected_tags)
        end
      end

      it 'joins the tags' do
        expect(described_class.joins(:tags).where(id: product).pluck('tags.id')).to match_array(expected_tags.map(&:id))
      end
    end

    context 'when the product is not deleted' do
      let(:expected_tags) { [non_deleted_tag] }

      it_behaves_like 'filters the tags'
    end

    context 'when the product is deleted' do
      let(:tag_deleted_together) { create(:tag) }
      let(:tags) { [non_deleted_tag, previously_deleted_tag, tag_deleted_together] }
      let(:expected_tags) { [tag_deleted_together] }

      before(:each) do
        product.destroy!
        tag_deleted_together.destroy!(deleted_in: product.deleted_in)
      end

      it_behaves_like 'filters the tags'
    end
  end

  describe 'association filtering with models that are not soft-deletable' do
    let(:product) { create(:product, :with_variants) }
    let(:non_deleted_variant_ids) { ProductVariant.where(product:).not_deleted.ids }
    let(:all_variant_ids) { ProductVariant.where(product:).ids }

    before(:each) do
      create(:product_variant, :deleted, product:)
    end

    def variant_ids(klass, name, loaded_by)
      case loaded_by
      when :owner then klass.find(product.id).public_send(name).map(&:id)
      when :preload, :eager_load then klass.public_send(loaded_by, name).find(product.id).public_send(name).map(&:id)
      when :joins then klass.joins(name).where(id: product.id).pluck('product_variants.id')
      end
    end

    context 'when the owner is not soft-deletable' do
      before(:each) do
        stub_const('PlainProduct', Class.new(ApplicationRecord) do
          self.table_name = 'products'

          SoftDeletable::AssociationCondition::MODES.each do |mode|
            has_many :"#{mode}_variants", class_name: 'ProductVariant', foreign_key: :product_id,
                                          includes_deleted: mode, inverse_of: false, dependent: nil
          end
        end)
      end

      %i[owner preload eager_load joins].each do |loaded_by|
        context "when loaded by #{loaded_by}" do
          it 'only includes variants that are not deleted for :never and :together', :aggregate_failures do
            expect(variant_ids(PlainProduct, :never_variants, loaded_by)).to match_array(non_deleted_variant_ids)
            expect(variant_ids(PlainProduct, :together_variants, loaded_by)).to match_array(non_deleted_variant_ids)
          end

          it 'includes all variants for :always' do
            expect(variant_ids(PlainProduct, :always_variants, loaded_by)).to match_array(all_variant_ids)
          end
        end
      end
    end

    context 'when the associated model is not soft-deletable' do
      before(:each) do
        stub_const('PlainVariant', Class.new(ApplicationRecord) { self.table_name = 'product_variants' })
        stub_const('SoftProduct', Class.new(ApplicationRecord) do
          self.table_name = 'products'
          include SoftDeletable::Model

          SoftDeletable::AssociationCondition::MODES.each do |mode|
            has_many :"#{mode}_variants", class_name: 'PlainVariant', foreign_key: :product_id,
                                          includes_deleted: mode, inverse_of: false, dependent: nil
          end
        end)

        product.destroy!
      end

      %i[owner preload eager_load joins].each do |loaded_by|
        context "when loaded by #{loaded_by}" do
          it 'includes all variants for every mode' do
            SoftDeletable::AssociationCondition::MODES.each do |mode|
              expect(variant_ids(SoftProduct, :"#{mode}_variants", loaded_by)).to match_array(all_variant_ids)
            end
          end
        end
      end
    end
  end
end
