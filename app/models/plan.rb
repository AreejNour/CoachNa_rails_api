# The `plans` table is shared with the Node API, which owns the client read and the canonical
# publish semantics. Rails authors drafts and replicates publish against the shared tables.
class Plan < ApplicationRecord
  belongs_to :subscription
  has_many :plan_options, -> { order(:position) }, dependent: :delete_all
end
