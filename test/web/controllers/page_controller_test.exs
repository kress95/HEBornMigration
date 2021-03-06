defmodule HEBornMigration.Web.PageControllerTest do
  use HEBornMigration.Web.ConnCase, async: true

  alias HEBornMigration.Repo

  alias HEBornMigration.Factory

  @moduletag :integration

  @secret Application.fetch_env!(:heborn_migration, :claim_secret)

  def get_token(conn) do
    conn
    |> get("/claim/#{@secret}/username")
    |> text_response(200)
  end

  describe "GET /" do
    test "returns the home page", %{conn: conn} do
      conn = get conn, "/"
      assert html_response(conn, 200) =~ "Migrate"
    end
  end

  describe "POST /" do
    test "succeeds returning the migration in progress page", %{conn: conn} do
      token = get_token(conn)

      params = %{
        account: %{
          token: token,
          email: "example@email.com",
          password: "12345678",
          password_confirmation: "12345678",
        }
      }

      conn = post(conn, "/", params)
      assert html_response(conn, 200) =~ "almost ready!"
    end

    test "fails returning the home page with input errors", %{conn: conn} do
      params = %{
        account: %{
          token: "",
          email: "",
          password: "",
          password_confirmation: "12345678",
        }
      }

      conn = post(conn, "/", params)
      assert html_response(conn, 200) =~ "Migrate"
    end
  end

  describe "GET /confirm" do
    test "returns the confirmation page", %{conn: conn} do
      conn = get conn, "/confirm"
      assert html_response(conn, 200) =~ "Finish your migration by confirming"
    end
  end

  describe "POST /confirm" do
    test "succeeds returning the migration completed page", %{conn: conn} do
      code =
        :account
        |> Factory.insert()
        |> Repo.preload(:confirmation)
        |> Map.fetch!(:confirmation)
        |> Map.fetch!(:code)

      params = %{confirmation: %{code: code}}

      conn = post(conn, "/confirm", params)
      assert html_response(conn, 200) =~ "Your HEBorn account is ready"
    end

    test "fails returning the confirm page with input errors", %{conn: conn} do
      params = %{confirmation: %{code: ""}}

      conn = post(conn, "/confirm", params)
      assert html_response(conn, 200) =~ "Finish your migration by confirming"
    end
  end

  describe "GET /claim/:secret/:username" do
    test "succeeds returning the token", %{conn: conn} do
      conn = get conn, "/claim/#{@secret}/username"
      assert text_response(conn, 200)
    end

    test "fails gracefully return 500 with invalid secret", %{conn: conn} do
      conn = get conn, "/claim/wat/username"
      assert text_response(conn, 500) =~ "Internal server error"
    end

    test "fails returning 500 with invalid name", %{conn: conn} do
      response = assert_error_sent 500, fn ->
        get conn, "/claim/#{@secret}/@invalid~username"
      end

      assert {500, _, body} = response
      assert body =~ "Internal server error"
    end
  end

  describe "GET /confirm/:code" do
    test "succeeds returning the migration completed page", %{conn: conn} do
      code =
        :account
        |> Factory.insert()
        |> Repo.preload(:confirmation)
        |> Map.fetch!(:confirmation)
        |> Map.fetch!(:code)

      conn = get(conn, "/confirm/#{code}")
      assert html_response(conn, 200) =~ "Your HEBorn account is ready"
    end

    test "fails returning the confirm page with input errors", %{conn: conn} do
      conn = get(conn, "/confirm/0")
      assert html_response(conn, 200) =~ "Finish your migration by confirming"
    end
  end
end
