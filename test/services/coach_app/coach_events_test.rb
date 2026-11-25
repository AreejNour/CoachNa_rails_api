require "test_helper"

class CoachApp::CoachEventsTest < ActiveSupport::TestCase
  setup do
    @coach = Coach.create!(full_name: "Sara", phone: "+201000000050", password_hash: "h", status: "approved")
  end

  {
    rejected:    { screen: "coach_status",  en_title: "Your application was declined",  en_body: "Open the app to see why." },
    suspended:   { screen: "coach_status",  en_title: "Your account is suspended",       en_body: "Open the app to see why." },
    reactivated: { screen: "coach_home",    en_title: "Your account is active again",    en_body: "You can take clients again." },
    deactivated: { screen: "coach_status",  en_title: "Your account was deactivated",    en_body: "Open the app to see why." }
  }.each do |event, expected|
    test "push_coach!(coach, :#{event}) enqueues the right push" do
      CoachApp::CoachEvents.push_coach!(@coach, event)

      push = OutboxMessage.find_by!(kind: "push").payload

      assert_equal({ "type" => "coach", "id" => @coach.id }, push["recipient"])
      assert push["title"]["ar"].present?,  "title.ar must be non-blank for :#{event}"
      assert push["title"]["en"].present?,  "title.en must be non-blank for :#{event}"
      assert push["body"]["ar"].present?,   "body.ar must be non-blank for :#{event}"
      assert push["body"]["en"].present?,   "body.en must be non-blank for :#{event}"
      assert_equal expected[:en_title], push["title"]["en"]
      assert_equal expected[:en_body],  push["body"]["en"]
      assert_equal({ "screen" => expected[:screen] }, push["data"])
    end
  end
end
