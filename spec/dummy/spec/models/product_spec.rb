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
end
