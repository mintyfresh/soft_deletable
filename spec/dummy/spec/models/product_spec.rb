# frozen_string_literal: true

# == Schema Information
#
# Table name: products
#
#  id            :integer          not null, primary key
#  created_by_id :integer          not null
#  name          :string           not null
#  price_cents   :integer          not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  deleted_at    :datetime
#  deleted_in    :string
#  deleted_by_id :integer
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
      let!(:live_variant) { create(:product_variant, product: deleted_product) }

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
            expect(products[deleted_product.id].variants).not_to include(live_variant)
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
        live_variant = create(:product_variant, product:)
        expect(product.live_variants).to contain_exactly(live_variant)
        expect(described_class.preload(:live_variants).find(product.id).live_variants).to contain_exactly(live_variant)
        expect(described_class.joins(:live_variants).where(id: product).pluck('product_variants.id'))
          .to contain_exactly(live_variant.id)
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
    let(:live_tag) { create(:tag) }
    let(:previously_deleted_tag) { create(:tag, :deleted) }
    let(:tags) { [live_tag, previously_deleted_tag] }

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
      let(:expected_tags) { [live_tag] }

      it_behaves_like 'filters the tags'
    end

    context 'when the product is deleted' do
      let(:tag_deleted_together) { create(:tag) }
      let(:tags) { [live_tag, previously_deleted_tag, tag_deleted_together] }
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
    let(:live_variant_ids) { ProductVariant.where(product:).not_deleted.ids }
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
            expect(variant_ids(PlainProduct, :never_variants, loaded_by)).to match_array(live_variant_ids)
            expect(variant_ids(PlainProduct, :together_variants, loaded_by)).to match_array(live_variant_ids)
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
