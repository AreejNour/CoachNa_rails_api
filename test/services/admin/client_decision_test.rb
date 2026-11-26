require "test_helper"

class Admin::ClientDecisionTest < ActiveSupport::TestCase
  def make_client(status, phone)
    Client.create!(full_name: "Test Client", phone: phone, password_hash: "h", status: status)
  end

  def make_token(client)
    ClientRefreshToken.create!(client_id: client.id, token: SecureRandom.hex(16), expires_at: 1.day.from_now)
  end

  test "suspend! moves active to suspended and deletes refresh tokens" do
    client = make_client("active", "+201000000201")
    make_token(client)
    make_token(client)

    Admin::ClientDecision.suspend!(client: client)

    assert_equal "suspended", client.reload.status
    assert_equal 0, ClientRefreshToken.where(client_id: client.id).count
  end

  test "reactivate! moves suspended to active and leaves tokens" do
    client = make_client("suspended", "+201000000202")
    make_token(client)

    Admin::ClientDecision.reactivate!(client: client)

    assert_equal "active", client.reload.status
    assert_equal 1, ClientRefreshToken.where(client_id: client.id).count
  end

  test "deactivate! from active sets deactivated and deletes tokens" do
    client = make_client("active", "+201000000203")
    make_token(client)

    Admin::ClientDecision.deactivate!(client: client)

    assert_equal "deactivated", client.reload.status
    assert_equal 0, ClientRefreshToken.where(client_id: client.id).count
  end

  test "deactivate! from suspended sets deactivated" do
    client = make_client("suspended", "+201000000204")

    Admin::ClientDecision.deactivate!(client: client)

    assert_equal "deactivated", client.reload.status
  end

  test "suspend! on a deactivated client raises and changes nothing" do
    client = make_client("deactivated", "+201000000205")

    assert_raises(Admin::ClientDecision::Error) { Admin::ClientDecision.suspend!(client: client) }
    assert_equal "deactivated", client.reload.status
  end

  test "reactivate! on an active client raises" do
    client = make_client("active", "+201000000206")
    assert_raises(Admin::ClientDecision::Error) { Admin::ClientDecision.reactivate!(client: client) }
    assert_equal "active", client.reload.status
  end

  test "deactivate! on a deactivated client raises" do
    client = make_client("deactivated", "+201000000207")
    assert_raises(Admin::ClientDecision::Error) { Admin::ClientDecision.deactivate!(client: client) }
    assert_equal "deactivated", client.reload.status
  end
end
