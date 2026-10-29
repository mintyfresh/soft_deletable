# frozen_string_literal: true

require 'rails_helper'
require 'tapioca/dsl/compilers/soft_deletable_relations'

RSpec.describe Tapioca::Dsl::Compilers::SoftDeletableRelations do
  subject(:rbi) do
    Tapioca::Dsl::Pipeline.new(requested_constants: [Product], requested_compilers:, number_of_workers: 1)
      .run { |_constant, file| Tapioca::DEFAULT_RBI_FORMATTER.print_file(file) }
      .first
  end

  let(:requested_compilers) { [Tapioca::Dsl::Compilers::ActiveRecordRelations, described_class] }
  let(:deletion_options) { 'deleted_in: SecureRandom.uuid, deleted_by: nil, permanent: false' }
  let(:deletion_option_types) { 'deleted_in: String, deleted_by: T.nilable(::ActiveRecord::Base), permanent: T::Boolean' }

  it 'replaces the generated delete_all methods with ones accepting deletion options' do
    expect(rbi.scan(/^ *def delete_all\b.*$/).map(&:strip)).to contain_exactly(
      "def delete_all(#{deletion_options}); end",
      "def delete_all(dependent = nil, #{deletion_options}); end"
    )
  end

  it 'replaces the generated destroy_all method with one accepting deletion options' do
    expect(rbi.scan(/^ *def destroy_all\b.*$/).map(&:strip)).to contain_exactly(
      "def destroy_all(#{deletion_options}); end"
    )
  end

  it 'types the deletion options', :aggregate_failures do
    expect(rbi).to include("sig { params(#{deletion_option_types}).returns(Integer) }")
    expect(rbi).to include("sig { params(#{deletion_option_types}).returns(T::Array[::Product]) }")
    expect(rbi).to include("sig { params(dependent: T.nilable(Symbol), #{deletion_option_types}).returns(Integer) }")
  end

  context 'when the ActiveRecordRelations compiler is not enabled' do
    let(:requested_compilers) { [described_class] }

    it 'generates nothing' do
      expect(rbi).to be_nil
    end
  end
end
