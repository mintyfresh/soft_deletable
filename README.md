# SoftDeletable
Manages soft-deletion of records, with cascading soft-deletion and restoration of associations.

## Installation
Add this line to your application's Gemfile:

```ruby
gem "soft_deletable"
```

And then execute:
```bash
$ bundle
```

Or install it yourself as:
```bash
$ gem install soft_deletable
```

Finally, to complete installation run:
```bash
$ bin/rails generate soft_deletable:install
```

This will create the SoftDeletable initializer file `config/initializers/soft_deletable`,
which should look something like this:
```ruby
# frozen_string_literal: true

SoftDeletable.configure do |config|
  # When using `dependent: :destroy_async` associations,
  # this is the queue that will be used by the `SoftDeletable::SoftDeleteAsyncJob`.
  # Defaults to `:default`.
  #
  # config.delete_job_queue = :default

  # When using `dependent: :destroy_async` associations,
  # this is the queue that will be used by the `SoftDeletable::RestoreAsyncJob`.
  # Defaults to `:default`.
  #
  # config.restore_job_queue = :default

  # The class name of the user model used by the `belongs_to :deleted_by` association.
  # Defaults to `'User'`.
  #
  # config.user_class_name = 'User'
end
```

## Usage

Add `SoftDeletable::Model` to your models:
```ruby
class Product < ApplicationRecord
  include SoftDeletable::Model

  # ...
end
```

Or, to make all models in your application soft-deletable, use:
```ruby
class ApplicationRecord < ActiveRecord::Base
  include SoftDeletable::Model

  # ...
end
```

### Migrations and Migration Helpers

SoftDeletable expects that each of your soft-deletable models have the following columns:
| Name          | Type      | Purpose |
| ------------- | --------- | ------- |
| deleted_at    | Timestamp | Indicates when the record was soft-deleted. Presence of a value indicates deletion (present = `true`, blank = `false`). |
| deleted_in    | UUID      | Indicates the transaction ID that deleted this record. Value is cascaded onto other soft-deletable records which were deleted in the same operation. This value is then used to cascade restore operations to only include records that were deleted by the same operation. (Value is not cleared upon restore.) |
| deleted_by_id | FK        | Tracks the user who deleted this record, via a `deleted_by` association. Value is cascaded onto other soft-deletable records which were deleted in the same operation. (Value is not cleared upon restore.) |

In service of this, the following migration helpers are available:
* `add_soft_deletable(table_name)` - Adds the soft-deletable columns to a table
* `remove_soft_deletable(table_name)` - Removes the soft-deletable columns from a table

For example:
```ruby
class AddSoftDeletableToProducts < ActiveRecord::Migration[8.0]
  def change
    add_soft_deletable :products # adds `deleted_at`, `deleted_in`, and `deleted_by_id`
  end
end
```

A `soft_deletable` table-definition helper is also available:
```ruby
class CreateProductVariants < ActiveRecord::Migration[8.0]
  def change
    create_table :product_variants do |t|
      t.belongs_to :product
      t.string :name
      t.integer :price_cents
      t.timestamps
      t.soft_deletable # adds `deleted_at`, `deleted_in`, and `deleted_by_id`
    end
  end
end
```

These migration helpers also accept the following keyword arguments:
| Name | Default Value | Comments |
| ---- | ------------- | -------- |
| `deleted_at_type` | `:timestamp` | The type of the `deleted_at` column. (e.g. If `:timestampz` is preferred.) |
| `deleted_in_type` | `:uuid` OR `:string` | UUID is used if supported by the database engine, otherwise stored as a string. |
| `deleted_by_type` | Configured PK type | Attempts to determine the configured PK type for the application, otherwise defaults to either `:bigint` or `:integer`, depending on database engine support. |
| `index` | `true` | Index options for `deleted_by_id`. May also accept a Hash. |
| `foreign_key` | `{ to_table: <users_table> }` | Foreign key options for `deleted_by_id`. `<users_table>` is determined by the configured user model. |

As an example with all arguments specified (for clarity only):
```ruby
add_soft_deletable(
  :products,
  deleted_at_type: :timestamp,
  deleted_in_type: :uuid,
  deleted_by_type: :uuid,
  index: true,
  foreign_key: { to_table: :users }
)
```

### Soft-Deletion

The `destroy`, `destroy!`, and `delete` methods are override for soft-deletable models to trigger soft-deletion.

For example, in a controlller, you might call these as:
```ruby
class ProductsController
  # ...

  def destroy
    @product.destroy!
    head :no_content
  end
end
```

However, it may be advantageous to track who deleted this record (ie. the `current_user`).
Furthermore, while a `deleted_in` value is automatically generated for the operation, there may be advantage to linking
the request ID back to this deletion (e.g. for future auditing or correlation with an APM):
```ruby
class ProductsController
  # ...

  def destroy
    @product.destroy!(deleted_by: current_user, deleted_in: request.request_id)
    head :no_content
  end
end
```

In addition, `restore`, `restore!`, and `undelete` are available as corresponding to the above methods,
to restore a previously soft-deleted record. With the exception of `undelete` (which corresponds to `delete` and thus does not fire callbacks),
these will also cascade un-deletion to their associations. See more in the section about dependent associations.

### Helpers

The following helpers are available to soft-deletable models:
* `deleted?` AND `deleted` - Attribute readers for the virtual `deleted` attribute (depends on the state of `deleted_at`)
* `deleted=` - Attribute writer for virtual `deleted` attribute
* `deleted_was`, `deleted_before_last_save`, `deleted_changed?`, and `saved_change_to_deleted?` - Attribute dirty-ness checks for virtual `deleted` attribute

### Callbacks

The following model callbacks are available to soft-deletable models:
* `before_soft_delete` - Triggered before a soft-deletable model is saved into its deleted state
* `after_soft_delete` - Same as above, but occurs after save
* `before_restore` - Triggered before a soft-deletable model is saved into its non-deleted state from its deleted state
* `after_restore` - Same as above, but occurs after save

In addition, the following transaction-level commit callbacks are available:
* `after_soft_delete_commit` - Triggered after a transction is committed in which the soft-deletable model was deleted
* `after_soft_delete_commit` - Triggered after a transction is committed in which the soft-deletable model was restored

### Dependent Associations

When using `has_one` and `has_many` associations, the following `dependent:` behaviours are supported for soft-deletable models:
* `:destroy` - Cascades soft-deletion to the associated records, triggering validations and callbacks for each of the dependent records.
* `:destroy_async` - Cascade soft-deletion via background jobs, triggering validations and callbacks for each of the dependent records.
* `:delete` or `:delete_all` - Cascade soft-deletion without triggering validations or callbacks on the dependent records.

**NOTE:** Dependent callbacks will _only_ be processed for other SoftDeletable models upon soft-deletion.

So, given the scenario:
```ruby
class Product < ApplicationRecord
  include SoftDeletable::Model

  has_many :orders, dependent: :destroy
end

class Order < ApplicationRecord
  # not soft-deletable

  belongs_to :product
end

product = Product.last

product.orders.count # => 5
product.destroy!
product.deleted? # => true
product.orders.count # => 5
```

This is to prevent unintentional and unanticipated deletions of non-soft-deletable records in a system that deals with both.
If hard-deletion of an associated record is desirable, a custom callback can be implemented to support this behaviour:
```ruby
class Product < ApplicationRecord
  include SoftDeletable::Model

  has_many :orders, dependent: :destroy

  after_soft_delete do
    orders.destroy_all
  end
end
```

## License
The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
