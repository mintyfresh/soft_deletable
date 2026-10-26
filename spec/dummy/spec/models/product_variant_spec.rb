# frozen_string_literal: true

# == Schema Information
#
# Table name: product_variants
#
#  id            :integer          not null, primary key
#  product_id    :integer          not null
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
#  index_product_variants_on_deleted_by_id  (deleted_by_id)
#  index_product_variants_on_product_id     (product_id)
#
# Foreign Keys
#
#  deleted_by_id  (deleted_by_id => users.id)
#  product_id     (product_id => products.id)
#
require 'rails_helper'

RSpec.describe ProductVariant, type: :model do
  subject(:product_variant) { build(:product_variant) }

  it { is_expected.to be_valid }

  describe 'counter cache' do
    let!(:product) { create(:product) }

    it 'increments the counter when a variant is created' do
      expect { create(:product_variant, product:) }.to change { product.reload.variants_count }.by(1)
    end

    it 'does not change the counter when a variant is created in a deleted state' do
      expect { create(:product_variant, :deleted, product:) }.not_to(change { product.reload.variants_count })
    end

    context 'with a non-deleted variant' do
      let!(:variant) { create(:product_variant, product:) }

      it 'decrements the counter when the variant is soft-deleted' do
        expect { variant.destroy }.to change { product.reload.variants_count }.by(-1)
      end

      it 'decrements the counter when the variant is hard-deleted' do
        expect { variant.destroy(permanent: true) }.to change { product.reload.variants_count }.by(-1)
      end

      it 'does not change the counter when the variant is deleted without callbacks' do
        expect { variant.delete }.not_to(change { product.reload.variants_count })
      end

      context 'when the variant is moved to another product' do
        let!(:other_product) { create(:product) }

        it 'moves the count to the other product' do
          expect { variant.update!(product: other_product) }
            .to change { product.reload.variants_count }.by(-1)
            .and change { other_product.reload.variants_count }.by(1)
        end

        it 'only decrements the original product when the variant is soft-deleted in the same save' do
          expect { variant.update!(product: other_product, deleted: true) }
            .to change { product.reload.variants_count }.by(-1)
            .and not_change { other_product.reload.variants_count }
        end
      end
    end

    context 'with a deleted variant' do
      let!(:deleted_variant) { create(:product_variant, :deleted, product:) }

      it 'increments the counter when the variant is restored' do
        expect { deleted_variant.restore! }.to change { product.reload.variants_count }.by(1)
      end

      it 'does not change the counter when the variant is soft-deleted again' do
        expect { deleted_variant.destroy }.not_to(change { product.reload.variants_count })
      end

      it 'does not change the counter when the variant is hard-deleted' do
        expect { deleted_variant.destroy(permanent: true) }.not_to(change { product.reload.variants_count })
      end

      context 'when the variant is moved to another product' do
        let!(:other_product) { create(:product) }

        it 'does not change either counter' do
          expect { deleted_variant.update!(product: other_product) }
            .to not_change { product.reload.variants_count }
            .and not_change { other_product.reload.variants_count }
        end

        it 'only increments the other product when the variant is restored in the same save' do
          expect { deleted_variant.update!(product: other_product, deleted: false) }
            .to not_change { product.reload.variants_count }
            .and change { other_product.reload.variants_count }.by(1)
        end
      end
    end
  end
end
