defmodule PauseAiCaWeb.Emails.Layout do
  @moduledoc """
  Wraps transactional email in the PauseAI Canada look.

  Email clients are a decade behind browsers, so this is deliberately plain:
  tables, inline styles, no web fonts, no external images. It should survive
  Outlook and still read as ours.

  Every message is bilingual. We do not know which language a recipient reads,
  and a sign-in link is the wrong place to guess.
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
    notice? = Keyword.get(opts, :notice, false)

    {html(title_en, title_fr, blocks, action, notice?),
     text(title_en, title_fr, blocks, action, notice?)}
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

  defp html(title_en, title_fr, blocks, action, notice?) do
    """
    <!DOCTYPE html>
    <html lang="en">
      <head><meta charset="utf-8" /><meta name="viewport" content="width=device-width" /></head>
      <body style="margin:0;padding:0;background:#{@paper};">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#{@paper};">
          <tr>
            <td align="center" style="padding:32px 16px;">
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0"
                     style="max-width:560px;background:#ffffff;border-radius:12px;overflow:hidden;">
                <tr>
                  <td style="background:#{@brand};padding:14px 24px;text-align:center;
                             font-family:Impact,'Helvetica Neue',Arial,sans-serif;font-size:13px;
                             letter-spacing:2px;text-transform:uppercase;color:#{@ink};font-weight:bold;">
                    PauseAI Canada
                  </td>
                </tr>
                <tr>
                  <td style="padding:32px 28px;font-family:Georgia,'Times New Roman',serif;
                             font-size:16px;line-height:1.6;color:#{@ink};">
                    <h1 style="margin:0 0 6px;font-family:Impact,'Helvetica Neue',Arial,sans-serif;
                               font-size:26px;line-height:1.2;color:#{@ink};">#{esc(title_en)}</h1>
                    <p style="margin:0 0 24px;font-family:Impact,'Helvetica Neue',Arial,sans-serif;
                              font-size:20px;line-height:1.25;color:#7a7268;">#{esc(title_fr)}</p>
                    #{Enum.map_join(blocks, "", &html_block/1)}
                    #{html_action(action)}
                    #{html_notice(notice?)}
                  </td>
                </tr>
                <tr>
                  <td style="padding:18px 28px 26px;border-top:1px solid #eceae4;
                             font-family:Georgia,serif;font-size:12px;line-height:1.55;color:#8a8378;">
                    pauseai.ca · info@pauseai.ca<br />
                    You are receiving this because someone asked to sign in with this address.<br />
                    Vous recevez ce message parce qu'une connexion a été demandée avec cette adresse.
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

  defp html_block({en, fr}) do
    """
    <p style="margin:0 0 10px;">#{esc(en)}</p>
    <p style="margin:0 0 22px;color:#6f675d;">#{esc(fr)}</p>
    """
  end

  # Yellow, bordered, and the instruction itself in bold: this is the one part
  # of the message we actively want people to act on.
  defp html_notice(false), do: ""

  defp html_notice(true) do
    {en, fr} = deliverability_notice()

    """
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0"
           style="margin:8px 0 4px;background:#fff8dc;border:1px solid #e6d27a;border-radius:8px;">
      <tr>
        <td style="padding:16px 18px;font-family:Georgia,serif;font-size:14px;line-height:1.55;color:#4a4034;">
          <p style="margin:0 0 8px;">📥 <strong>#{esc(en)}</strong></p>
          <p style="margin:0;color:#6b5f4e;">#{esc(fr)}</p>
        </td>
      </tr>
    </table>
    """
  end

  defp html_action(nil), do: ""

  defp html_action({label_en, label_fr, url}) do
    """
    <table role="presentation" cellpadding="0" cellspacing="0" style="margin:8px 0 24px;">
      <tr>
        <td style="background:#{@brand};border-radius:999px;">
          <a href="#{esc(url)}"
             style="display:inline-block;padding:14px 30px;font-family:Impact,'Helvetica Neue',Arial,sans-serif;
                    font-size:17px;letter-spacing:0.5px;color:#{@ink};text-decoration:none;">
            #{esc(label_en)} · #{esc(label_fr)}
          </a>
        </td>
      </tr>
    </table>
    <p style="margin:0 0 6px;font-size:13px;color:#8a8378;">
      If the button does not work, paste this into your browser:<br />
      Si le bouton ne fonctionne pas, collez ceci dans votre navigateur&nbsp;:
    </p>
    <p style="margin:0 0 22px;font-size:13px;word-break:break-all;"><a href="#{esc(url)}"
       style="color:#b35f00;">#{esc(url)}</a></p>
    """
  end

  defp text(title_en, title_fr, blocks, action, notice?) do
    body =
      Enum.map_join(blocks, "\n\n", fn {en, fr} -> "#{en}\n\n#{fr}" end)

    action_text =
      case action do
        nil -> ""
        {_label_en, _label_fr, url} -> "\n\n#{url}\n"
      end

    notice_text =
      if notice? do
        {en, fr} = deliverability_notice()

        "\n-----------------------------------------------------------\n#{en}\n\n#{fr}\n-----------------------------------------------------------\n"
      else
        ""
      end

    """
    PauseAI Canada
    ==============

    #{title_en}
    #{title_fr}

    #{body}#{action_text}#{notice_text}
    --
    pauseai.ca · info@pauseai.ca
    You are receiving this because someone asked to sign in with this address.
    Vous recevez ce message parce qu'une connexion a été demandée avec cette adresse.
    """
  end

  defp esc(value) do
    value |> to_string() |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
  end
end
