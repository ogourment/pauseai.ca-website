defmodule PauseAiCaWeb.MPTemplateLive do
  use PauseAiCaWeb, :live_view
  alias PauseAiCa.MPTemplates

  def mount(_, _, socket), do: {:ok, socket}

  def handle_params(params, _, socket) do
    locale = if socket.assigns.live_action == :fr, do: "fr", else: "en"
    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)

    campaign =
      case MPTemplates.published(params["slug"], locale, params["revision"]) do
        {:ok, published} -> published
        _ -> nil
      end

    alternate = if locale == "fr", do: "en", else: "fr"

    translated =
      if campaign,
        do: MPTemplates.share_path(campaign.slug, alternate, campaign.revision),
        else: "/#{alternate}"

    path = if locale == "fr", do: "/fr/contacter-votre-depute", else: "/en/contact-your-mp"

    letter_path =
      if campaign,
        do:
          path <> "?" <> URI.encode_query(%{template: campaign.slug, revision: campaign.revision})

    {:noreply,
     assign(socket,
       locale: locale,
       campaign: campaign,
       completed_count: if(campaign, do: MPTemplates.completed_count(campaign.id), else: 0),
       translated_path: translated,
       letter_path: letter_path,
       page_title:
         if(campaign, do: campaign.title, else: gettext("Campaign template unavailable"))
     )}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      locale={@locale}
      translated_path={@translated_path}
    >
      <section id="mp-campaign-template" class="mx-auto max-w-3xl space-y-6 px-5 py-10">
        <article :if={@campaign} class="space-y-5">
          <h1 class="font-heading text-3xl">{@campaign.title}</h1>
          <p id="mp-template-purpose" class="whitespace-pre-wrap break-words">{@campaign.purpose}</p>
          <p id="mp-template-completed-count" class="text-sm text-stone-600">
            {ngettext(
              "%{count} letter sent or confirmed",
              "%{count} letters sent or confirmed",
              @completed_count
            )}
          </p>
          <dl class="space-y-2 break-words">
            <div>
              <dt class="inline font-semibold">{gettext("Author")}</dt>

              <dd class="inline" id="mp-template-author">{@campaign.author}</dd>
            </div>
            <div>
              <dt class="inline font-semibold">{gettext("Source")}</dt>

              <dd class="inline">
                <a
                  id="mp-template-source"
                  href={@campaign.source}
                  rel="noopener noreferrer"
                  target="_blank"
                  class="underline break-all"
                >{@campaign.source}</a>
              </dd>
            </div>
            <div>
              <dt class="inline font-semibold">{gettext("Published revision")}</dt>

              <dd class="inline" id="mp-template-public-revision">{@campaign.revision}</dd>
            </div>
          </dl>
          <p>{gettext("Personalize this campaign letter for your own representative.")}</p>
          <.link id="mp-template-personalize" href={@letter_path} class="btn btn-primary">{gettext(
            "Personalize this letter"
          )}</.link>
          <section class="space-y-3 rounded-xl border p-5 min-w-0">
            <h2 class="font-heading text-xl">{@campaign.subject}</h2>
            <div id="mp-template-public-body" class="prose max-w-none break-words">
              {raw(@campaign.html)}
            </div>
          </section>
          <p>{gettext("Share this published version")}</p>
          <.link id="mp-template-share" href={@campaign.share_path} class="underline break-all">{PauseAiCaWeb.Site.url(
            @locale,
            @campaign.share_path
          )}</.link>
        </article>
        <section :if={is_nil(@campaign)} id="mp-template-unavailable" class="space-y-3">
          <h1 class="font-heading text-2xl">{gettext("Campaign template unavailable")}</h1>
          <p>{gettext("Choose a published campaign link to open its reviewed letter.")}</p>
        </section>
      </section>
    </Layouts.app>
    """
  end
end
