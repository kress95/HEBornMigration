defmodule HEBornMigration.Web.Account do

  use Ecto.Schema

  alias Comeonin.Bcrypt
  alias HEBornMigration.Web.Claim
  alias HEBornMigration.Web.Confirmation

  import Ecto.Changeset

  @type id :: pos_integer

  @type t :: %__MODULE__{
    id: pos_integer,
    email: String.t,
    username: String.t,
    display_name: String.t,
    password: String.t,
    confirmed: boolean,
    inserted_at: NaiveDateTime.t,
    updated_at: NaiveDateTime.t
  }

  # unconfirmed account expire date
  @expiration_time 2 * 24 * 60 * 60

  schema "accounts" do
    field :email, :string
    field :username, :string
    field :display_name, :string
    field :password, :string
    field :password_confirmation, :string,
      virtual: true
    field :confirmed, :boolean,
      default: false

    has_one :confirmation, Confirmation,
      foreign_key: :id

    timestamps()
  end

  @spec create(Claim.t, String.t, String.t, String.t) ::
    Ecto.Changeset.t
  @doc """
  Creates Account to be migrated.
  """
  def create(claim = %Claim{}, email, password, password_confirmation) do
    params = %{
      claim: claim,
      email: email,
      password: password,
      password_confirmation: password_confirmation
    }

    %__MODULE__{}
    |> changeset(params)
    |> validate_confirmation(:password, required: true,
      message: "does not match password")
    |> put_assoc(:confirmation, Confirmation.create())
  end
  def create(nil, email, password, password_confirmation) do
    %Claim{token: "", display_name: ""}
    |> create(email, password, password_confirmation)
    |> add_error(:token, "is invalid")
  end

  @spec confirm(t) ::
    Ecto.Changeset.t
  @doc """
  Confirms existing account.
  """
  def confirm(struct),
    do: changeset(struct, %{confirmed: true})

  @spec expired?(t) ::
    boolean
  @doc """
  Checks if the account is unconfirmed for more than 48 hours.
  """
  def expired?(struct) do
    now = NaiveDateTime.utc_now()
    NaiveDateTime.diff(now, struct.inserted_at) > @expiration_time
  end

  @spec format_error(Ecto.Changeset.t) ::
    %{atom => [String.t]}
  @doc """
  Formats changeset errors
  """
  def format_error(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  @doc false
  def changeset(struct, params) do
    # no display_name validation is being done here as it was already
    # validated on Claim model
    struct
    |> cast(params, [:display_name, :email, :password, :confirmed])
    |> put_display_name_from_claim(params)
    |> propagate_change(:display_name, :username, &String.downcase/1)
    |> unique_constraint(:username)
    |> validate_change(:email, &validate_email/2)
    |> update_change(:email, &String.downcase/1)
    |> unique_constraint(:email)
    |> validate_length(:password, min: 8)
    |> update_change(:password, &Bcrypt.hashpwsalt/1)
    |> validate_required([:display_name, :username, :email, :password])
  end

  # puts diplay_name from claim
  defp put_display_name_from_claim(changeset, %{claim: claim}) do
    case claim do
      %Claim{} ->
        put_change(changeset, :display_name, claim.display_name)
      _ ->
        changeset
    end
  end
  defp put_display_name_from_claim(changeset, _) do
    changeset
  end

  # propagates a change to another field, optionall accepts a mapping function
  defp propagate_change(changeset, from, to, fun) do
    case fetch_change(changeset, from) do
      {:ok, value} ->
        put_change(changeset, to, fun.(value))
      :error ->
        changeset
    end
  end

  @spec validate_email(:email, String.t) ::
    []
    | [email: String.t]
  # Validates that the email is a valid email address
  #
  # TODO: Remove this regex and use something better
  defp validate_email(:email, value) do
    is_binary(value)
    && Regex.match?(~r/^[\w0-9\.\-\_\+]+@[\w0-9\.\-\_]+\.[\w0-9\-]+$/ui, value)
    && []
    || [email: "has invalid format"]
  end
end
