# SoftDeletable

Manages soft-deletion of records, with cascading soft-deletion and restoration of associations.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'soft_deletable', source: 'https://rubygems.pkg.github.com/mintyfresh'
```

Or use the latest version directly from Github:

```ruby
gem 'soft_deletable', github: 'mintyfresh/soft_deletable'
```

(Unfortunately, there's a dead package occupying the name on Rubygems.)

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

  # Whether `dependent: :restrict_with_exception` and `dependent: :restrict_with_error` associations
  # allow soft-deletion despite non-deleted associated records (hard-deletion is always restricted).
  # Can be overridden per association with the `skip_restriction_on_soft_delete:` option.
  # Defaults to `false`.
  #
  # config.skip_restriction_on_soft_delete = false

  # Whether hard-deleting a record which is not soft-deletable may hard-delete its soft-deletable dependents
  # (otherwise `SoftDeletable::PermanentCascadeError` is raised).
  # Can be overridden per association with the `allow_permanent_delete:` option.
  # Defaults to `false`.
  #
  # config.allow_permanent_delete = false
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


| Name          | Type      | Purpose                                                                                                                                                                                                                                                                                                          |
| ------------- | --------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| deleted_at    | Timestamp | Indicates when the record was soft-deleted. Presence of a value indicates deletion (present = `true`, blank = `false`).                                                                                                                                                                                          |
| deleted_in    | UUID      | Indicates the transaction ID that deleted this record. Value is cascaded onto other soft-deletable records which were deleted in the same operation. This value is then used to cascade restore operations to only include records that were deleted by the same operation. (Value is not cleared upon restore.) |
| deleted_by_id | FK        | Tracks the user who deleted this record, via a `deleted_by` association. Value is cascaded onto other soft-deletable records which were deleted in the same operation. (Value is not cleared upon restore.)                                                                                                      |


In service of this, the following migration helpers are available:

- `add_soft_deletable(table_name)` - Adds the soft-deletable columns to a table
- `remove_soft_deletable(table_name)` - Removes the soft-deletable columns from a table

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


| Name              | Default Value                 | Comments                                                                                                                                                      |
| ----------------- | ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `deleted_at_type` | `:timestamp`                  | The type of the `deleted_at` column. (e.g. If `:timestampz` is preferred.)                                                                                    |
| `deleted_in_type` | `:uuid` OR `:string`          | UUID is used if supported by the database engine, otherwise stored as a string.                                                                               |
| `deleted_by_type` | Configured PK type            | Attempts to determine the configured PK type for the application, otherwise defaults to either `:bigint` or `:integer`, depending on database engine support. |
| `index`           | `true`                        | Index options for `deleted_by_id`. May also accept a Hash.                                                                                                    |
| `foreign_key`     | `{ to_table: <users_table> }` | Foreign key options for `deleted_by_id`. `<users_table>` is determined by the configured user model.                                                          |


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

**NOTE:** The migration helper will **not** produce an index on the `deleted_at` column nor the `deleted_in` column.
SoftDeletable treats `deleted_at` as a boolean flag; `true` if the value is present, `false` otherwise.
This is based on the presuppositions that:

- Most records in your database tables are not deleted
- Most queries will access records using an index with greater cardinality than a boolean would produce (e.g. via an index on a foreign key)
- Restoring deleted records is an uncommon operation
- Most of the queries involved in cascading a restore will use an index over the associations' foreign keys

If these conditions are not true for your tables or application, you may wish to consider introducing additional indices as necessary. In scenarios where a large majority of the records in a table are soft-deleted, partial indices are preferred if your database supports them (e.g. `add_index :carts, :product_id, where: 'deleted_at IS NULL'` or similar).

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

`delete_all` is also overridden for relations of soft-deletable models (e.g. `Product.delete_all` or `Product.where(...).delete_all`),
soft-deleting the records which are not already deleted in a single operation, without triggering validations or callbacks:

```ruby
Product.where(created_by: user).delete_all(deleted_by: current_user, deleted_in: request.request_id)
```

Relations of soft-deletable models can be restored in the same way:

- `restore_all` - Restores the deleted records in the relation, triggering validations and callbacks and cascading un-deletion for each record. Returns the restored records.
- `restore_by(...)` - Shorthand for `where(...).restore_all`, as with `destroy_by`
- `undelete_all` - Restores the deleted records in the relation in a single query, without triggering validations or callbacks. Returns the number of restored records.

```ruby
Product.deleted.where(deleted_by: user).restore_all
Product.restore_by(deleted_in: request_id)
```

Since a record's associations are filtered by its deleted state, the deleted associated records of a non-deleted record must be restored through a relation which includes them (e.g. `product.variants.unscope_deleted.restore_all`).

#### Permanent Deletion

Each of `destroy`, `destroy!`, `delete`, `delete_all`, and `destroy_all` accept a `permanent: true` argument to hard-delete records instead:

```ruby
product.destroy!(permanent: true)
product.variants.delete_all(permanent: true) # only the variants loaded by the association
Product.deleted.where(deleted_at: ...1.year.ago).delete_all(permanent: true)
```

`destroy_all` (on relations and collection associations) and collection `delete_all` also accept `deleted_by:` and `deleted_in:`.
`destroy_all` soft-deletes its records in a single operation (ie. with a shared `deleted_in`), so they are restored together.
Passing any of these options to a `has_many :through` association, or to `delete_all` with `:nullify`, raises an `ArgumentError`,
since those don't delete the associated records.

`mark_for_destruction(permanent: true)` marks a record to be hard-deleted when its owner is saved.
As with ActiveRecord, this requires the association to autosave (e.g. `autosave: true`, or `accepts_nested_attributes_for`).
Without `permanent`, the record is instead soft-deleted when it is next saved.

Hard-deletion cascades to dependent associations according to their `dependent:` option, as with ActiveRecord.
Unlike soft-deletion, this includes associated records which were already soft-deleted, since they would otherwise be orphaned.

Hard-deleting a record which is *not* soft-deletable will not cascade to dependent soft-deletable records,
and raises `SoftDeletable::PermanentCascadeError` instead, to prevent unintentional loss of soft-deletable records.
If this is desirable, use the `allow_permanent_delete:` option (which defaults to `config.allow_permanent_delete`):

```ruby
class Order < ApplicationRecord
  # not soft-deletable

  has_many :line_items, dependent: :destroy, allow_permanent_delete: true # LineItem is soft-deletable
end
```

This also allows a concern to declare the association for owners which may or may not be soft-deletable:

```ruby
module Commentable
  extend ActiveSupport::Concern

  included do
    # soft-deletes comments with soft-deletable owners, and hard-deletes them otherwise
    has_many :comments, as: :commentable, dependent: :destroy, allow_permanent_delete: true
  end
end
```



### Helpers

The following helpers are available to soft-deletable models:

- `deleted?` AND `deleted` - Attribute readers for the virtual `deleted` attribute (depends on the state of `deleted_at`)
- `deleted=` - Attribute writer for virtual `deleted` attribute
- `deleted_in_database` (and alias `deleted_in_database?`) - Equivalent to `attribute_in_database(:deleted_at).present?`
- `deleted_was`, `deleted_before_last_save`, `deleted_changed?`, and `saved_change_to_deleted?` - Attribute dirty-ness checks for virtual `deleted` attribute



### Callbacks

The following model callbacks are available to soft-deletable models:

- `before_soft_delete` - Triggered before a soft-deletable model is saved into its deleted state
- `after_soft_delete` - Same as above, but occurs after save
- `before_restore` - Triggered before a soft-deletable model is saved into its non-deleted state from its deleted state
- `after_restore` - Same as above, but occurs after save

In addition, the following transaction-level commit callbacks are available:

- `after_soft_delete_commit` - Triggered after a transction is committed in which the soft-deletable model was deleted
- `after_restore_commit` - Triggered after a transction is committed in which the soft-deletable model was restored



### Associations

When the associated model is a soft-deletable model, the associated records are filtered by the deleted state of the record they are loaded from:

- When the record is not deleted - Only associated records which are not deleted are included
- When the record is deleted - Only associated records which were deleted in the same operation (ie. with the same `deleted_in`) are included

This applies when loading an association from a record (e.g. `product.variants`), as well as to `joins`, `includes`, `preload`, and `eager_load`.

So, given the scenario:

```ruby
class Product < ApplicationRecord
  include SoftDeletable::Model

  has_many :variants, class_name: 'ProductVariant', dependent: :destroy
end

class ProductVariant < ApplicationRecord
  include SoftDeletable::Model

  belongs_to :product
end

product = Product.last

product.variants.count # => 5
product.variants.first.destroy!
product.variants.count # => 4
product.destroy!
product.deleted? # => true
product.variants.count # => 4

ProductVariant.deleted.count # => 5
ProductVariant.deleted.group(:deleted_in).count.count # => 2 (operations)
```



#### Includes Deleted

The `includes_deleted:` option controls how an association is filtered by deleted state:

- `:never` - Only associated records which are not deleted are included, regardless of the deleted state of the record they are loaded from
- `:together` - Associated records are filtered by the deleted state of the record they are loaded from, as described above
- `:always` - Associated records are included regardless of their deleted state (ie. no filtering is applied)

It defaults to `:together` for `has_one`, `has_many`, and `has_and_belongs_to_many` associations, and `:always` for `belongs_to` associations:

```ruby
class Product < ApplicationRecord
  include SoftDeletable::Model

  has_many :variants, class_name: 'ProductVariant', dependent: :destroy
  has_many :non_deleted_variants, class_name: 'ProductVariant', includes_deleted: :never
  has_many :all_variants, class_name: 'ProductVariant', includes_deleted: :always
end

class ProductVariant < ApplicationRecord
  include SoftDeletable::Model

  belongs_to :product, includes_deleted: :together
end
```

When `includes_deleted: :together` is specified for a `belongs_to` association, deleted records will also include associated records which are not deleted
(ie. a variant which was deleted on its own will still include its product).

**NOTE:** Associations will *only* be filtered for other SoftDeletable models. All three options may still be specified for associations with non-soft-deletable models (e.g. in a concern that is shared between both), in which case:

- When the associated model is not soft-deletable - All three options have no effect
- When the record an association is loaded from is not soft-deletable - It is treated as not deleted, so `:never` and `:together` only include associated records which are not deleted, and `:always` has no effect



#### Dependent Associations

When using `has_one` and `has_many` associations, the following `dependent:` behaviours are supported for soft-deletable models:

- `:destroy` - Cascades soft-deletion to the associated records, triggering validations and callbacks for each of the dependent records.
- `:destroy_async` - Cascade soft-deletion via background jobs, triggering validations and callbacks for each of the dependent records.
- `:delete` or `:delete_all` - Cascade soft-deletion without triggering validations or callbacks on the dependent records.
- `:restrict_with_exception` - Raises `ActiveRecord::DeleteRestrictionError` if any non-deleted records are associated.
- `:restrict_with_error` - Adds an error to the record and halts soft-deletion if any non-deleted records are associated
(`destroy` returns `false`, and `destroy!` raises `ActiveRecord::RecordNotDestroyed`).

**NOTE:** Cascading dependent callbacks will *only* be processed for other SoftDeletable models upon soft-deletion.
Restrictions apply to any associated records, but previously soft-deleted records never restrict soft-deletion.

To restrict only hard-deletion, use the `skip_restriction_on_soft_delete:` option
(which defaults to `config.skip_restriction_on_soft_delete`):

```ruby
class Customer < ApplicationRecord
  include SoftDeletable::Model

  has_many :orders, dependent: :restrict_with_exception, skip_restriction_on_soft_delete: true
end
```

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



#### Counter Caches

When a `belongs_to` association of a soft-deletable model specifies `counter_cache:`, the counter only counts records which are not deleted:

- Soft-deleting a record decrements the counter, and restoring it increments the counter
- Records which are created in a deleted state are not counted
- Hard-deleting a record which was already soft-deleted does not decrement the counter
- Moving a deleted record to another associated record does not change either counter

```ruby
class Product < ApplicationRecord
  include SoftDeletable::Model

  has_many :variants, class_name: 'ProductVariant', dependent: :destroy
end

class ProductVariant < ApplicationRecord
  include SoftDeletable::Model

  belongs_to :product, counter_cache: :variants_count
end

product = Product.last

product.variants_count # => 5
product.variants.first.destroy!
product.reload.variants_count # => 4
```

As with ActiveRecord, operations which skip callbacks (e.g. `delete`, `undelete`, `delete_all`, and `dependent: :delete_all`) do not update counters.
Mixing these with operations which run callbacks on the same record (e.g. soft-deleting a record with `delete` and then restoring it with `restore`) will cause the counter to drift.

The counter cache is not used to size the associations of a deleted record (e.g. `product.variants.size`),
since they include the records which were deleted in the same operation.

## Comparison with Other Gems

SoftDeletable is based on my own personally stylistic and behavioural preferences when it comes to soft-deletion.
I'm not a fan of messing with default scopes in Rails at all, I'm of the opinion that hard-deletion of soft-deletable records is a rare edge-case,
I like the way Rails manages dependency within associations and want soft-deletable records to behave the same way,
and for one reason or another, I'm not a particuarly big fan of the way other gems perform this function.

That said, not everyone shares these opinions, and there's plenty of other options to consider, each which their own slightly different way of doing things:


| Feature                             | SoftDeletable                                                                                       | [paranoia](https://github.com/rubysherpas/paranoia)                                                           | [acts_as_paranoid](https://github.com/ActsAsParanoid/acts_as_paranoid) | [discard](https://github.com/jhawthorn/discard) | [permanent_records](https://github.com/JackDanger/permanent_records) |
| ----------------------------------- | --------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------- | ----------------------------------------------- | -------------------------------------------------------------------- |
| Default scope hides deleted records | No (`not_deleted` scope)                                                                            | Yes (opt-out with `without_default_scope`)                                                                    | Yes                                                                    | No (`kept` scope)                               | No (`not_deleted` scope)                                             |
| `#destroy` soft-deletes             | Yes                                                                                                 | Yes                                                                                                           | Yes                                                                    | No (`discard` instead)                          | Yes                                                                  |
| `#delete` soft-deletes              | Yes (without callbacks)                                                                             | Yes (without callbacks)                                                                                       | Yes (without callbacks, freezes the record)                            | No (hard-deletes)                               | No (hard-deletes)                                                    |
| Relation `.delete_all` soft-deletes | Yes                                                                                                 | Opt-in (`delete_all_enabled`)                                                                                 | Yes                                                                    | No (`discard_all` instead)                      | No                                                                   |
| Hard-deletion                       | `destroy(permanent: true)`                                                                          | `really_destroy!`                                                                                             | `destroy_fully!`, or destroying twice                                  | `destroy`                                       | `destroy(:force)`                                                    |
| Cascading soft-deletion             | `dependent: :destroy`, `:destroy_async`, `:delete`, and `:delete_all` (soft-deletable records only) | `dependent: :destroy` (non-paranoid records are hard-deleted)                                                 | `dependent: :destroy`                                                  | No (manual, via callbacks)                      | `dependent: :destroy`                                                |
| Cascading hard-deletion             | Raises `PermanentCascadeError` (opt-in to hard-delete with `allow_permanent_delete:`)               | Soft-deletes (via `destroy`)                                                                                  | Soft-deletes (via `destroy`)                                           | Hard-deletes                                    | Hard-deletes (via `destroy(:force)`)                                 |
| `dependent: :restrict_with_*`       | Yes, by non-deleted records (opt-out with `skip_restriction_on_soft_delete:`)                       | Yes (via `destroy` callbacks)                                                                                 | Yes (via `destroy` callbacks)                                          | No (`discard` skips `destroy` callbacks)        | Yes (via `destroy` callbacks)                                        |
| Cascading restoration               | Deterministic, records deleted in the same operation (`deleted_in`)                                 | Heuristic, opt-in (`recursive: true`), all deleted dependents or those deleted within an optional time window | Heuristic, records deleted within a time window                        | No (manual, via callbacks)                      | Heuristic, records deleted within a time window                      |
| Deleted-state-aware associations    | Automatic, including joins and eager-loading                                                        | Manual (`belongs_to :x, -> { with_deleted }`)                                                                 | `belongs_to :x, with_deleted: true`                                    | Manual (via joins)                              | Manual                                                               |
| Nested attributes (`_destroy`)      | Yes, soft-deletes in the same save (via `mark_for_destruction`)                                     | Yes, soft-deletes (via `destroy`)                                                                             | Yes, soft-deletes (via `destroy`)                                      | No (hard-deletes)                               | Yes, soft-deletes (via `destroy`)                                    |
| Counter caches                      | Yes, only counts non-deleted records                                                                | Yes, only counts non-deleted records                                                                          | Yes, double-counts hard deletion                                       | No (counts kept and discarded records)          | Yes, double-counts hard deletion                                     |
| Tracks who deleted a record         | Yes (`deleted_by`)                                                                                  | No                                                                                                            | No                                                                     | No                                              | No                                                                   |
| Callbacks                           | `soft_delete`, `restore`, and commit variants                                                       | `destroy`, `restore`, `real_destroy`, and `restore_commit`                                                    | `destroy` and `recover`                                                | `discard` and `undiscard`                       | `destroy`                                                            |
| Deletion column(s)                  | `deleted_at` (plus `deleted_in` and `deleted_by_id`)                                                | `deleted_at` (configurable, supports sentinel values)                                                         | `deleted_at` (configurable, time, boolean, or string)                  | `discarded_at` (configurable)                   | `deleted_at`                                                         |
| Sorbet/Tapioca compatibility        | Yes, via inline RBS (compiled into RBIs by Tapioca), plus a Tapioca DSL compiler for relations      | No signatures                                                                                                 | No signatures                                                          | Callback shims only (via `tapioca annotations`) | No signatures                                                        |




## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).