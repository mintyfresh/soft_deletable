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
            user.created_products.pluck(:id),
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
            user.created_products.pluck(:id)
          )
      end

      it 'excludes any previously deleted products from the job', :aggregate_failures do
        other_product = create(:product, :deleted, created_by: user, deleted_in: SecureRandom.uuid)
        expect(restore).to be_truthy
        expect(SoftDeletable::RestoreAsyncJob).to have_been_enqueued
          .on_queue(SoftDeletable.config.restore_job_queue)
          .with(
            Product.name,
            user.created_products.excluding(other_product).pluck(:id)
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
            user.created_products.pluck(:id)
          )
      end
    end
  end
end
