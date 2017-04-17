defmodule HEBornMigration.Web.AccountController do

  alias HEBornMigration.Repo
  alias HEBornMigration.Web.Account
  alias HEBornMigration.Web.Claim
  alias HEBornMigration.Web.Confirmation

  @spec claim(display_name :: String.t) ::
    {:ok, token :: String.t}
    | {:error, Ecto.Changeset.t}
  @doc """
  Claims account with given `display_name`, returns a token string to be
  used for migration.

  Reclaiming an unconfirmed account is possible after 48 hours, this feature
  allows players that typed wrong emails to retry their migrations.
  """
  def claim(display_name) do
    changeset = Claim.create(display_name)

    with \
      nil <- Repo.get_by(Claim, display_name: display_name),
      nil <- Repo.get_by(Account, username: String.downcase(display_name)),
      {:ok, claim} <- Repo.insert(changeset)
    do
      {:ok, claim.token}
    else
      {:error, changeset} ->
        {:error, changeset}

      claim = %Claim{} ->
        {:ok, claim.token}

      account = %Account{} ->
        account
        |> Account.expired?()
        |> maybe_expire_account(account, changeset)
    end
  end

  @spec migrate(Claim.t | String.t, String.t, String.t, String.t) ::
    {:ok, Account.t}
    | {:error, Ecto.Changeset.t}
  @doc """
  Migrates claimed account, sends an e-mail with the confirmation code.
  """
  def migrate(token, email, password, password_confirmation)
  when is_binary(token) do
    token
    |> Claim.Query.by_token()
    |> Repo.one()
    |> migrate(email, password, password_confirmation)
  end
  def migrate(claim, email, password, password_confirmation) do
    Repo.transaction fn ->
      result =
        claim
        |> Account.create(email, password, password_confirmation)
        |> Repo.insert()

      case result do
        {:ok, account} ->
          Repo.delete!(claim)
          account
        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end
  end

  @spec confirm(Confirmation.t | String.t) ::
    {:ok, Account.t}
    | {:error, Ecto.Changeset.t}
  @doc """
  Confirms an already migrated account.

  The expiration date doesn't affect this function, as it's just intented to
  help users that wrongly typed their emails.
  """
  def confirm(confirmation = %Confirmation{}) do
    Repo.transaction(fn ->
      changeset =
        confirmation
        |> Repo.preload(:account)
        |> Confirmation.confirm()

      case Repo.update(changeset) do
        {:ok, confirmation} ->
          Repo.delete!(confirmation)
          confirmation.account
        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end
  def confirm(code) do
    result =
      code
      |> Confirmation.Query.by_code()
      |> Repo.one()

    case result do
      nil ->
        changeset = Confirmation.code_error(code)
        {:error, changeset}
      confirmation ->
        confirm(confirmation)
    end
  end

  # replaces an expired unconfirmed account
  @spec maybe_expire_account(expire? :: boolean, Account.t, Ecto.Changeset.t) ::
    {:ok, Claim.token}
    | {:error, Ecto.Changeset.t}
  defp maybe_expire_account(true, account, changeset) do
    Repo.transaction fn ->
      Repo.delete!(account)

      case Repo.insert(changeset) do
        {:ok, claim} ->
          claim.token
        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end
  end
  defp maybe_expire_account(false, _, changeset)  do
    changeset = Ecto.Changeset.add_error(
      changeset,
      :display_name,
      "has been taken")

    {:error, changeset}
  end
end
