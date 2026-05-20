defmodule EzagentWeb.Mailer do
  @moduledoc """
  Username & Auth M2 — outbound email.

  SMTP relay + credentials are NOT in compile-time config — they live
  in `Ezagent.AppSettings` (`"smtp_config"`), set by the admin in the
  Phase 8 settings UI at runtime. `deliver_magic_link/2` reads that
  config and passes it to `Swoosh.Mailer.deliver/2` as a per-delivery
  override.
  """
  use Swoosh.Mailer, otp_app: :ezagent_web

  import Swoosh.Email

  @doc """
  Build (do not send) the magic-link email. Pure — unit-testable.

  Opts: `:url` (the magic link), `:from_address`.
  """
  @spec build_magic_link_email(String.t(), keyword()) :: Swoosh.Email.t()
  def build_magic_link_email(to_email, opts) do
    url = Keyword.fetch!(opts, :url)
    from_address = Keyword.fetch!(opts, :from_address)

    new()
    |> to(to_email)
    |> from({"Ezagent", from_address})
    |> subject("Your Ezagent sign-in link")
    |> text_body("""
    Sign in to Ezagent by opening this link (valid for 15 minutes):

    #{url}

    If you did not request this, you can ignore this email.
    """)
    |> html_body("""
    <p>Sign in to Ezagent by opening this link (valid for 15 minutes):</p>
    <p><a href="#{url}">#{url}</a></p>
    <p style="color:#888;font-size:12px;">If you did not request this, ignore this email.</p>
    """)
  end

  @doc """
  Build + deliver the magic-link email using the runtime SMTP config.

  Returns `{:error, :smtp_not_configured}` if the admin has not set
  SMTP up yet — callers MUST treat this as "do not proceed".
  """
  @spec deliver_magic_link(String.t(), String.t()) ::
          {:ok, term()} | {:error, term()}
  def deliver_magic_link(to_email, url) do
    case Ezagent.AppSettings.get("smtp_config") do
      %{} = cfg ->
        if Ezagent.AppSettings.smtp_configured?() do
          email =
            build_magic_link_email(to_email,
              url: url,
              from_address: Map.fetch!(cfg, "from_address")
            )

          deliver(email, smtp_runtime_config(cfg))
        else
          {:error, :smtp_not_configured}
        end

      _ ->
        {:error, :smtp_not_configured}
    end
  end

  # Map the stored smtp_config map into Swoosh.Adapters.SMTP options.
  defp smtp_runtime_config(cfg) do
    [
      relay: Map.fetch!(cfg, "host"),
      port: to_int(Map.fetch!(cfg, "port")),
      username: Map.fetch!(cfg, "username"),
      password: Map.fetch!(cfg, "password"),
      auth: :always,
      tls: if(Map.get(cfg, "tls", true), do: :always, else: :never),
      ssl: false
    ]
  end

  defp to_int(n) when is_integer(n), do: n
  defp to_int(s) when is_binary(s), do: String.to_integer(String.trim(s))
end
