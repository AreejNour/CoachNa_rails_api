# The `messages` table is shared with the Node API. sender_type is 'client' or 'coach';
# a message carries a body and/or a photo attachment. client_ref makes a retried send idempotent.
class Message < ApplicationRecord
  belongs_to :conversation

  def photo? = attachment_key.present?
end
