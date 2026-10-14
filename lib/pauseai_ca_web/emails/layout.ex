defmodule PauseAiCaWeb.Emails.Layout do
  @moduledoc """
  Wraps transactional email in the PauseAI Canada look.

  Email clients are a decade behind browsers, so this is deliberately plain:
  tables, inline styles, no web fonts, no external images. It should survive
  Outlook and still read as ours.

  Pass `locale: "en"` or `locale: "fr"` for a single-language message.
  Messages without a known locale retain both languages.
  """

  @brand "#f68b1e"
  @ink "#1c1917"
  @paper "#f8f5ed"

  @doc """
  Returns `{html, text}` for a message.

  `blocks` is a list of `{english, french}` paragraph pairs. `action` is an
  optional `{label_en, label_fr, url}` button. Pass `notice: true` to include
  the spam-folder guidance; see `deliverability_notice/0`.
  """
  @spec render(String.t(), String.t(), [{String.t(), String.t()}], tuple() | nil, keyword()) ::
          {String.t(), String.t()}
  def render(title_en, title_fr, blocks, action \\ nil, opts \\ []) do
    locale = Keyword.get(opts, :locale)
    notice? = Keyword.get(opts, :notice, false)
    {title_en, title_fr} = edition({title_en, title_fr}, locale)
    blocks = Enum.map(blocks, &edition(&1, locale))
    action = localize_action(action, locale, Keyword.get(opts, :language_actions, false))

    footer =
      Keyword.get(
        opts,
        :footer,
        {"You are receiving this because someone asked to sign in with this address.",
         "Vous recevez ce message parce qu'une connexion a été demandée avec cette adresse."}
      )

    footer = edition(footer, locale)
    links = Keyword.get(opts, :footer_links, [])

    {html(
       title_en,
       title_fr,
       blocks,
       action,
       notice?,
       footer,
       Keyword.get(opts, :body_html, ""),
       links,
       locale,
       opts
     ),
     text(
       title_en,
       title_fr,
       blocks,
       action,
       notice?,
       footer,
       Keyword.get(opts, :body_text, ""),
       links,
       locale
     )}
  end

  @doc """
  The spam-folder guidance shown on a recipient's first message.

  Asking someone to move a message out of spam is not only for their benefit:
  every "not spam" is a signal to their provider, and on a young sending domain
  those signals are most of what reputation is built from.
  """
  @spec deliverability_notice() :: {String.t(), String.t()}
  def deliverability_notice do
    {"Did this land in spam or promotions? Please move it to your inbox and mark it \"Not spam\". It takes a second, and it is how we stay out of the spam folder for everyone else.",
     "Ce message est-il arrivé dans les indésirables ou les promotions? Déplacez-le vers votre boîte de réception et marquez-le « Non indésirable ». Cela prend une seconde, et c'est ainsi que nous évitons le dossier spam pour tout le monde."}
  end

  defp html(
         title_en,
         title_fr,
         blocks,
         action,
         notice?,
         {footer_en, footer_fr},
         body_html,
         links,
         locale,
         opts
       ) do
    font = Keyword.get(opts, :font_family, "Georgia,'Times New Roman',serif")

    heading_font =
      Keyword.get(opts, :heading_font_family, "Impact,'Helvetica Neue',Arial,sans-serif")

    width = Keyword.get(opts, :width, 560)

    """
    <!DOCTYPE html>
    <html lang="#{locale || "en"}">
      <head><meta charset="utf-8" /><meta name="viewport" content="width=device-width" /></head>
      <body style="margin:0;padding:0;background:#{@paper};">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#{@paper};">
          <tr>
            <td align="center" style="padding:32px 16px;">
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0"
                     style="max-width:#{width}px;table-layout:fixed;background:#ffffff;border-radius:12px;overflow:hidden;">
                <tr>
                  <td style="background:#{@brand};padding:14px 24px;text-align:center;
                             font-family:#{heading_font};font-size:13px;
                             letter-spacing:2px;text-transform:uppercase;color:#{@ink};font-weight:bold;">
                    PauseAI Canada
                  </td>
                </tr>
                <tr>
                  <td style="padding:32px 28px;font-family:#{font};overflow-wrap:anywhere;word-break:break-word;
                             font-size:16px;line-height:1.6;color:#{@ink};">
                    <h1 style="margin:0 0 6px;font-family:#{heading_font};
                               font-size:26px;line-height:1.2;color:#{@ink};">#{esc(title_en)}</h1>
                    #{secondary_title(title_fr)}
                    #{body_html}
                    #{Enum.map_join(blocks, "", &html_block/1)}
                    #{html_action(action)}
                    #{html_notice(notice?, locale)}
                  </td>
                </tr>
                <tr>
                  <td style="padding:18px 28px 26px;border-top:1px solid #eceae4;
                             font-family:#{font};font-size:12px;line-height:1.55;color:#57534e;">
                    pauseai.ca · info@pauseai.ca<br />
                    #{Enum.map_join(present([footer_en, footer_fr]), "<br />", &esc/1)}
                    #{html_links(links)}
                  </td>
                </tr>
              </table>
            </td>
          </tr>
        </table>
      </body>
    </html>
    """
  end

  defp html_block(pair) do
    pair
    |> Tuple.to_list()
    |> present()
    |> Enum.map_join("", fn value ->
      "<p style=\"margin:0 0 16px;\">#{esc(value)}</p>"
    end)
  end

  defp secondary_title(nil), do: ""

  defp secondary_title(value),
    do: "<p style=\"margin:0 0 24px;font-size:20px;color:#7a7268;\">#{esc(value)}</p>"

  # Yellow, bordered, and the instruction itself in bold: this is the one part
  # of the message we actively want people to act on.
  defp html_notice(false, _locale), do: ""

  defp html_notice(true, locale) do
    {en, fr} = edition(deliverability_notice(), locale)

    """
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0"
           style="margin:8px 0 4px;background:#fff8dc;border:1px solid #e6d27a;border-radius:8px;">
      <tr>
        <td style="padding:16px 18px;font-family:Georgia,serif;font-size:14px;line-height:1.55;color:#4a4034;">
          #{html_block({en, fr})}
        </td>
      </tr>
    </table>
    """
  end

  defp html_action(nil), do: ""

  defp html_action({en, fr, url, :language_choices}) do
    html_action({en, nil, language_url(url, "en"), "en"}) <>
      html_action({fr, nil, language_url(url, "fr"), "fr"})
  end

  defp html_action({label_en, label_fr, url, locale}) do
    """
    <table role="presentation" cellpadding="0" cellspacing="0" style="margin:8px 0 24px;">
      <tr>
        <td style="background:#{@brand};border-radius:999px;">
          <a href="#{esc(url)}"
             style="display:inline-block;padding:14px 30px;font-family:Impact,'Helvetica Neue',Arial,sans-serif;
                    font-size:17px;letter-spacing:0.5px;color:#{@ink};text-decoration:none;">
            #{present([label_en, label_fr]) |> Enum.map_join(" · ", &esc/1)}
          </a>
        </td>
      </tr>
    </table>
    <div style="margin:0 0 6px;font-size:13px;color:#8a8378;">
      #{html_block(edition({"If the button does not work, paste this into your browser:", "Si le bouton ne fonctionne pas, collez ceci dans votre navigateur :"}, locale))}
    </div>
    <p style="margin:0 0 22px;font-size:13px;word-break:break-all;"><a href="#{esc(url)}"
       style="color:#b35f00;">#{esc(url)}</a></p>
    """
  end

  defp html_links(links) do
    Enum.map_join(links, "", fn {label, url} ->
      "<p style=\"margin:8px 0 0;font-size:12px;\"><a href=\"#{esc(url)}\" style=\"color:#854d0e;text-decoration:underline;\">#{esc(label)}</a></p>"
    end)
  end

  defp text(
         title_en,
         title_fr,
         blocks,
         action,
         notice?,
         {footer_en, footer_fr},
         body_text,
         links,
         locale
       ) do
    body =
      Enum.map_join(blocks, "\n\n", fn pair ->
        pair |> Tuple.to_list() |> present() |> Enum.join("\n\n")
      end)

    action_text =
      case action do
        nil ->
          ""

        {en, fr, url, :language_choices} ->
          "\n\n#{en}:\n#{language_url(url, "en")}\n\n#{fr}:\n#{language_url(url, "fr")}\n"

        {label_en, label_fr, url, _locale} ->
          "\n\n#{present([label_en, label_fr]) |> Enum.join(" · ")}:\n#{url}\n"
      end

    notice_text =
      if notice? do
        {en, fr} = edition(deliverability_notice(), locale)

        "\n-----------------------------------------------------------\n#{present([en, fr]) |> Enum.join("\n\n")}\n-----------------------------------------------------------\n"
      else
        ""
      end

    """
    PauseAI Canada
    ==============

    #{present([title_en, title_fr]) |> Enum.join("\n")}

    #{body_text}

    #{body}#{action_text}#{notice_text}
    --
    pauseai.ca · info@pauseai.ca
    #{present([footer_en, footer_fr]) |> Enum.join("\n")}
    #{Enum.map_join(links, "\n", fn {label, url} -> "#{label}: #{url}" end)}
    """
  end

  defp edition({en, _fr}, "en"), do: {en, nil}
  defp edition({_en, fr}, "fr"), do: {fr, nil}
  defp edition(pair, _), do: pair
  defp present(values), do: Enum.reject(values, &is_nil/1)
  defp localize_action(nil, _, _), do: nil

  defp localize_action({en, fr, url}, locale, language_actions?) do
    {first, second} = edition({en, fr}, locale)

    {first, second, url,
     if(is_nil(locale) and language_actions?, do: :language_choices, else: locale)}
  end

  defp language_url(url, locale) do
    uri = URI.parse(url)
    query = URI.decode_query(uri.query || "") |> Map.put("locale", locale) |> URI.encode_query()
    URI.to_string(%{uri | query: query})
  end

  defp esc(value) do
    value |> to_string() |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
  end
end
