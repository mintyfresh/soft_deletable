# frozen_string_literal: true

# == Schema Information
#
# Table name: users
#
#  id            :integer          not null, primary key
#  email         :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  deleted_at    :datetime
#  deleted_in    :string
#  deleted_by_id :integer
#
# Indexes
#
#  index_users_on_deleted_by_id  (deleted_by_id)
#  index_users_on_email          (email) UNIQUE
#
# Foreign Keys
#
#  deleted_by_id  (deleted_by_id => users.id)
#
require 'rails_helper'

RSpec.describe User, type: :model do
  subject(:user) { build(:user) }

  it { is_expected.to be_valid }

  describe '#destroy' do
    subject(:destroy) { user.destroy }

    let(:user) { create(:user) }

    before(:each) do
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    end

    it 'soft-deletes the user', :aggregate_failures do
      expect(destroy).to be_truthy
      expect(user).to be_deleted.and have_attributes(
        deleted_in: be_present,
        deleted_by: nil
      )
    end

    context 'with a deleted-by user' do
      subject(:destroy) { user.destroy(deleted_by:) }

      let(:deleted_by) { create(:user) }

      it 'sets the deleted-by user', :aggregate_failures do
        expect(destroy).to be_truthy
        expect(user).to be_deleted.and have_attributes(
          deleted_in: be_present,
          deleted_by:
        )
      end
    end

    context 'with a deleted-in value' do
      subject(:destroy) { user.destroy(deleted_in:) }

      let(:deleted_in) { SecureRandom.uuid }

      it 'sets the deleted-in value', :aggregate_failures do
        expect(destroy).to be_truthy
        expect(user).to be_deleted.and have_attributes(
          deleted_in:,
          deleted_by: nil
        )
      end
    end

    context 'with associated created products' do
      let(:user) { create(:user, :with_created_products) }

      it 'soft-deletes the user', :aggregate_failures do
        expect(destroy).to be_truthy
        expect(user).to be_deleted.and have_attributes(
          deleted_in: be_present,
          deleted_by: nil
        )
      end

      it 'enqueues a job to soft-delete the created products', :aggregate_failures do
        expect(destroy).to be_truthy
        expect(SoftDeletable::SoftDeleteAsyncJob).to have_been_enqueued
          .on_queue(SoftDeletable.config.delete_job_queue)
          .with(
            Product.name,
            match_array(user.created_products.pluck(:id)),
            deleted_in: user.deleted_in,
            deleted_by: user.deleted_by
          )
      end

      context 'when permanent' do
        subject(:destroy) { user.destroy(permanent: true) }

        let!(:previously_deleted_product) { create(:product, :deleted, created_by: user) }

        # destroy_async leaves dependents in place until the job runs, as it does in Rails
        around(:each) do |example|
          ActiveRecord::Base.connection.disable_referential_integrity { example.run }
        end

        it 'enqueues a job to hard-delete the created products, including soft-deleted ones', :aggregate_failures do
          product_ids = Product.where(created_by_id: user.id).ids

          expect(destroy).to be_truthy
          expect(described_class.exists?(user.id)).to be(false)
          expect(product_ids).to include(previously_deleted_product.id)
          expect(SoftDeletable::SoftDeleteAsyncJob).to have_been_enqueued
            .with(Product.name, match_array(product_ids), permanent: true)
        end

        it 'hard-deletes the created products when the job runs' do
          product_ids = Product.where(created_by_id: user.id).ids

          destroy
          SoftDeletable::SoftDeleteAsyncJob.perform_now(Product.name, product_ids, permanent: true)
          expect(Product.where(id: product_ids)).to be_empty
        end
      end
    end
  end

  describe '#save' do
    subject(:save) { user.save }

    before(:each) do
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    end

    context 'when the record is created in a deleted state' do
      let(:user) { build(:user, :deleted, :with_created_products) }

      it 'soft-deletes all the created products', :aggregate_failures do
        expect(save).to be_truthy
        expect(user.created_products).to all be_persisted.and be_deleted.and have_attributes(
          deleted_in: user.deleted_in,
          deleted_by: user.deleted_by
        )
      end

      it "doesn't enqueue a job for the unsaved products", :aggregate_failures do
        expect(save).to be_truthy
        expect(SoftDeletable::SoftDeleteAsyncJob).not_to have_been_enqueued
      end
    end

    context 'when the record is created in a deleted state with already-saved products' do
      let(:user) { build(:user, :deleted) }
      let(:created_products) { create_list(:product, 2) }

      before(:each) do
        user.created_products = created_products
      end

      it 'enqueues a job to soft-delete the saved products', :aggregate_failures do
        expect(save).to be_truthy
        expect(SoftDeletable::SoftDeleteAsyncJob).to have_been_enqueued
          .on_queue(SoftDeletable.config.delete_job_queue)
          .with(
            Product.name,
            created_products.map(&:id),
            deleted_in: user.deleted_in,
            deleted_by: user.deleted_by
          )
      end
    end
  end

  describe '#restore' do
    subject(:restore) { user.restore }

    let(:user) { create(:user, :deleted) }

    before(:each) do
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    end

    it 'restores the user', :aggregate_failures do
      expect(restore).to be_truthy
      expect(user).not_to be_deleted
    end

    context 'with associated created products' do
      let(:user) { create(:user, :deleted, :with_created_products) }

      it 'restores the user', :aggregate_failures do
        expect(restore).to be_truthy
        expect(user).not_to be_deleted
      end

      it 'enqueues a job to restore the created products', :aggregate_failures do
        expect(restore).to be_truthy
        expect(SoftDeletable::RestoreAsyncJob).to have_been_enqueued
          .on_queue(SoftDeletable.config.restore_job_queue)
          .with(
            Product.name,
            match_array(user.created_products.pluck(:id))
          )
      end

      it 'excludes any previously deleted products from the job', :aggregate_failures do
        other_product = create(:product, :deleted, created_by: user, deleted_in: SecureRandom.uuid)
        expect(restore).to be_truthy
        expect(SoftDeletable::RestoreAsyncJob).to have_been_enqueued
          .on_queue(SoftDeletable.config.restore_job_queue)
          .with(
            Product.name,
            match_array(Product.where(created_by: user).excluding(other_product).pluck(:id))
          )
      end
    end

    context 'with associated created products that have variants' do
      let(:user) { create(:user, :deleted, :with_created_products, created_products_traits: [:with_variants]) }

      it 'restores the user', :aggregate_failures do
        expect(restore).to be_truthy
        expect(user).not_to be_deleted
      end

      it 'enqueues a job to restore the created products', :aggregate_failures do
        restore
        expect(SoftDeletable::RestoreAsyncJob).to have_been_enqueued
          .on_queue(SoftDeletable.config.restore_job_queue)
          .with(
            Product.name,
            match_array(user.created_products.pluck(:id))
          )
      end
    end
  end

  describe '#created_product_variants.delete_all' do
    let(:user) { create(:user, :with_created_products, created_products_traits: [:with_variants]) }

    it 'rejects deletion options for a through association', :aggregate_failures do
      expect { user.created_product_variants.delete_all(permanent: true) }
        .to raise_error(ArgumentError, /does not support deletion options/)
      expect(Product.where(created_by_id: user.id).count).to eq(3)
      expect(ProductVariant.joins(:product).where(products: { created_by_id: user.id }).count).to eq(9)
    end
  end

  describe '#created_product_variants.destroy_all' do
    let(:user) { create(:user, :with_created_products, created_products_traits: [:with_variants]) }

    it 'rejects deletion options for a through association', :aggregate_failures do
      expect { user.created_product_variants.destroy_all(permanent: true) }
        .to raise_error(ArgumentError, /does not support deletion options/)
      expect(Product.where(created_by_id: user.id).count).to eq(3)
      expect(ProductVariant.joins(:product).where(products: { created_by_id: user.id }).count).to eq(9)
    end
  end

  describe 'through association filtering' do
    let(:user) { create(:user, :with_created_products, created_products_traits: [:with_variants]) }
    let(:product) { user.created_products.first }
    let!(:previously_deleted_variant) { create(:product_variant, :deleted, product:) }
    let!(:variant_of_deleted_product) do
      deleted_product = create(:product, :deleted, created_by: user)
      create(:product_variant, product: deleted_product)
    end
    let(:non_deleted_variants) { ProductVariant.where(product: user.created_products).not_deleted }

    shared_examples 'filters every step' do
      it 'only includes variants that are not deleted, of products that are not deleted', :aggregate_failures do
        expect(variants).to match_array(non_deleted_variants)
        expect(variants).not_to include(previously_deleted_variant, variant_of_deleted_product)
      end
    end

    context 'when loaded from the user' do
      let(:variants) { user.reload.created_product_variants }

      it_behaves_like 'filters every step'
    end

    %i[preload eager_load].each do |method|
      context "when loaded with #{method}" do
        let(:variants) do
          described_class.public_send(method, :created_product_variants).find(user.id).created_product_variants
        end

        it_behaves_like 'filters every step'
      end
    end

    context 'when joined' do
      let(:variants) do
        joined = described_class.joins(:created_product_variants).where(id: user).select('product_variants.id')
        ProductVariant.where(id: joined)
      end

      it_behaves_like 'filters every step'
    end

    context 'when the user is deleted' do
      let(:user) { create(:user, :deleted, :with_created_products, created_products_traits: [:with_variants]) }

      it 'only includes variants deleted in the same operation', :aggregate_failures do
        expect(user.reload.created_product_variants).to be_present.and all have_attributes(
          deleted: true, deleted_in: user.deleted_in
        )
        expect(user.created_product_variants).not_to include(previously_deleted_variant, variant_of_deleted_product)
      end
    end

    context 'with includes_deleted' do
      it 'is not allowed' do
        expect do
          described_class.has_many :all_variants, through: :created_products, source: :variants, includes_deleted: true
        end.to raise_error(ArgumentError, /cannot use includes_deleted on a through association/)
      end
    end
  end
end
