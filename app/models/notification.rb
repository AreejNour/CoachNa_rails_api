# In-app notifications, shared with the Node API, for every kind of account. `type` is a plain
# column (the notification kind), not Rails STI. Node writes coach notifications (e.g. new_client);
# Rails reads them and marks them read.
class Notification < ApplicationRecord
  self.inheritance_column = nil
end
