defmodule PauseAiCaWeb.AdminInteracDonationsLive do
  use PauseAiCaWeb, :live_view
  alias PauseAiCa.Donations.Interac
  alias PauseAiCaWeb.{DonationPageContent, VolunteerForms}

  def mount(params, _, socket) do
    locale = PauseAiCaWeb.Site.locale(params, socket)
    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)

    {:ok,
     assign(socket,
       locale: locale,
       page_title: gettext("Interac donations"),
       declarations: [],
       summary: %{pending: 0, verified: 0, received_minor: 0},
       declaration: nil,
       form: nil,
       confirmed_received: false,
       page: 1,
       more: false
     )}
  end

  def handle_params(params, _, socket) do
    page =
      case Integer.parse(params["page"] || "1") do
        {page, ""} when page > 0 and page < 100_000 -> page
        _ -> 1
      end

    with {:ok, rows} <- Interac.list(socket.assigns.current_scope, page),
         {:ok, summary} <- Interac.summary(socket.assigns.current_scope),
         {:ok, declaration} <- selected(socket.assigns.current_scope, params["id"]) do
      {:noreply,
       assign(socket,
         page: page,
         declarations: Enum.take(rows, 25),
         more: length(rows) > 25,
         summary: summary,
         declaration: declaration,
         confirmed_received: false,
         form: verification_form(declaration)
       )}
    else
      _ -> denied(socket)
    end
  end

  def handle_event("verify_receipt", _, %{assigns: %{declaration: nil}} = socket),
    do: denied(socket)

  def handle_event("verify_receipt", %{"verification" => attrs}, socket) do
    attrs = Map.reject(attrs, fn {key, _} -> String.starts_with?(key, "_unused_") end)

    if attrs["confirmed_received"] != "true" do
      {:noreply,
       socket
       |> assign(form: to_form(attrs, as: "verification"))
       |> put_flash(:error, gettext("Confirm that you checked the deposit in the bank account."))}
    else
      revision =
        case Integer.parse(attrs["revision"] || "") do
          {revision, ""} -> revision
          _ -> nil
        end

      case Interac.verify(
             socket.assigns.current_scope,
             socket.assigns.declaration.id,
             attrs,
             revision
           ) do
        {:ok, declaration} ->
          {:ok, summary} = Interac.summary(socket.assigns.current_scope)

          {:noreply,
           assign(socket,
             declaration: declaration,
             summary: summary,
             confirmed_received: false,
             form: verification_form(declaration)
           )}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply,
           assign(socket,
             form: to_form(%{changeset | action: :update}, as: "verification"),
             confirmed_received: true
           )}

        {:error, :unauthorized} ->
          denied(socket)

        {:error, reason} when reason in [:stale, :already_verified] ->
          {:noreply,
           put_flash(
             socket,
             :error,
             gettext("This record has changed. Reload it before verifying.")
           )}

        {:error, _} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             gettext("The bank receipt could not be verified. Review the fields and try again.")
           )}
      end
    end
  end

  defp selected(_, nil), do: {:ok, nil}
  defp selected(scope, id), do: Interac.get(scope, id)
  defp verification_form(nil), do: nil

  defp verification_form(declaration) do
    to_form(
      %{
        "received_amount" =>
          decimal_amount(declaration.received_minor || declaration.amount_minor),
        "received_on" => Date.to_iso8601(declaration.received_on || Date.utc_today()),
        "bank_reference" => declaration.bank_reference || "",
        "verification_note" => declaration.verification_note || ""
      },
      as: "verification"
    )
  end

  defp decimal_amount(minor),
    do:
      "#{div(minor, 100)}.#{minor |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")}"

  defp denied(socket),
    do:
      {:noreply,
       socket
       |> put_flash(:error, gettext("You do not have access to this page."))
       |> redirect(to: ~p"/dashboard")}

  def render(assigns) do
    ~H"""
    <Layouts.management
      flash={@flash}
      current_scope={@current_scope}
      locale={@locale}
      active_tab="interac-donations"
    >
      <section id="interac-donations" class="crm-surface mx-auto max-w-6xl px-5 py-8">
        <h1 class="text-3xl font-bold">{gettext("Interac donations")}</h1>
        <p class="mt-3">
          {gettext(
            "Private matching records. A declaration is pending until an administrator verifies the actual bank deposit."
          )}
        </p>
        <dl class="my-5 flex flex-wrap gap-6 rounded-lg border border-stone-300 p-4">
          <div>
            <dt>{gettext("Pending declarations")}</dt><dd id="interac-pending-count" class="font-bold">
              {@summary.pending}
            </dd>
          </div>
          <div>
            <dt>{gettext("Bank-verified receipts")}</dt><dd
              id="interac-verified-count"
              class="font-bold"
            >
              {@summary.verified}
            </dd>
          </div>
          <div>
            <dt>{gettext("Verified amount received")}</dt><dd
              id="interac-received-total"
              class="font-bold"
            >
              {DonationPageContent.money(@summary.received_minor, @locale)}
            </dd>
          </div>
        </dl>
        <%= if @declaration do %>
          <.link
            navigate={~p"/admin/interac-donations?#{%{locale: @locale, page: @page}}"}
            class="underline"
          >{gettext("Back to declarations")}</.link>
          <article
            id={"interac-record-#{@declaration.id}"}
            class="mt-5 space-y-4 rounded-lg border border-stone-300 p-5"
          >
            <h2 class="text-xl font-bold">{@declaration.name || gettext("Linked account")}</h2>
            <p class="break-words">{@declaration.email}</p>
            <p :if={@declaration.account_ref}>
              <.link
                href={~p"/manage/accounts/#{@declaration.account_ref}?#{%{locale: @locale}}"}
                class="underline"
              >{gettext("View linked account")}</.link>
            </p>
            <p>
              {gettext("Declared amount")}:
              <strong>{DonationPageContent.money(@declaration.amount_minor, @locale)}</strong>
            </p>
            <p>
              {gettext("Anonymous donation")}:
              <strong>{if @declaration.anonymous, do: gettext("Yes"), else: gettext("No")}</strong>
            </p>
            <p class="text-sm">
              {gettext(
                "Anonymous donations retain private matching details. No public donor list is created."
              )}
            </p>
            <p>
              {gettext("Submitted")}:
              <VolunteerForms.timestamp
                id="interac-submitted"
                value={@declaration.submitted_at}
                locale={@locale}
              />
            </p>
            <%= if @declaration.state == "verified" do %>
              <section id="interac-verified-receipt" class="rounded-lg bg-brand-wash p-4">
                <h3 class="font-bold">{gettext("Bank receipt verified")}</h3>
                <p>
                  {DonationPageContent.money(@declaration.received_minor, @locale)} ·
                  <time datetime={Date.to_iso8601(@declaration.received_on)}>{Date.to_iso8601(
                    @declaration.received_on
                  )}</time>
                </p>
                <p :if={@declaration.bank_reference} class="break-words">
                  {gettext("Bank reference")}: {@declaration.bank_reference}
                </p>
                <p :if={!@declaration.bank_reference} class="text-sm">
                  {gettext(
                    "No bank reference was recorded. Duplicate receipts cannot be checked by reference."
                  )}
                </p>
                <p :if={@declaration.verification_note} class="whitespace-pre-wrap break-words">
                  {@declaration.verification_note}
                </p>
                <p>
                  <VolunteerForms.timestamp
                    id="interac-verified-at"
                    value={@declaration.verified_at}
                    locale={@locale}
                  />
                </p>
              </section>
            <% else %>
              <.form
                for={@form}
                id="interac-verification-form"
                phx-submit="verify_receipt"
                class="space-y-4"
              >
                <input type="hidden" name="verification[revision]" value={@declaration.revision} />
                <h3 class="font-bold">{gettext("Match the bank deposit")}</h3>
                <div class="grid gap-4 sm:grid-cols-2">
                  <.input
                    field={@form[:received_amount]}
                    label={gettext("Amount received (CAD)")}
                    inputmode="decimal"
                    required
                  />
                  <.input
                    field={@form[:received_on]}
                    label={gettext("Date received")}
                    type="date"
                    required
                  />
                </div>
                <.input
                  field={@form[:bank_reference]}
                  label={gettext("Bank reference (optional)")}
                  maxlength="255"
                />
                <p class="text-sm">
                  {gettext(
                    "Use the bank’s actual reference when available. Without it, check manually for a duplicate receipt."
                  )}
                </p>
                <.input
                  field={@form[:verification_note]}
                  label={gettext("Private verification note (optional)")}
                  type="textarea"
                  maxlength="2000"
                />
                <.input
                  type="checkbox"
                  id="interac-confirmed-received"
                  name="verification[confirmed_received]"
                  value={@confirmed_received}
                  label={gettext("I checked this deposit in the bank account.")}
                />
                <button type="submit" class="crm-button" phx-disable-with={gettext("Verifying…")}>{gettext(
                  "Verify bank receipt"
                )}</button>
              </.form>
            <% end %>
          </article>
        <% else %>
          <p :if={@declarations == []}>{gettext("No Interac declarations on this page.")}</p>
          <article
            :for={declaration <- @declarations}
            id={"interac-declaration-#{declaration.id}"}
            class="my-3 rounded-lg border border-stone-300 p-4"
          >
            <.link
              navigate={
                ~p"/admin/interac-donations/#{declaration.id}?#{%{locale: @locale, page: @page}}"
              }
              class="font-bold underline"
            >{declaration.name || gettext("Linked account")}</.link>
            <p class="break-words">
              {declaration.email} · {DonationPageContent.money(declaration.amount_minor, @locale)}
            </p>
            <p>
              {if declaration.state == "verified",
                do: gettext("Bank receipt verified"),
                else: gettext("Awaiting bank verification")}
            </p>
          </article>
          <nav class="mt-5 flex gap-4" aria-label={gettext("Pagination")}>
            <.link
              :if={@page > 1}
              patch={~p"/admin/interac-donations?#{%{page: @page - 1, locale: @locale}}"}
              class="underline"
            >{gettext("Previous")}</.link>
            <.link
              :if={@more}
              patch={~p"/admin/interac-donations?#{%{page: @page + 1, locale: @locale}}"}
              class="underline"
            >{gettext("Next")}</.link>
          </nav>
        <% end %>
      </section>
    </Layouts.management>
    """
  end
end
