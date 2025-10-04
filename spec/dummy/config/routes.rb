# frozen_string_literal: true

Rails.application.routes.draw do
  mount SoftDeletable::Engine => '/soft_deletable'
end
