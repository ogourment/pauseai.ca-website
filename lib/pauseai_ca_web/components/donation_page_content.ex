defmodule PauseAiCaWeb.DonationPageContent do
  @moduledoc "Published donation content and an inert CMS preview share one consumer rendering."
  use PauseAiCaWeb, :html

  attr :page, :map, required: true
  attr :locale, :string, required: true
  attr :preview_mode, :boolean, default: false
  attr :gift_minor, :integer, default: 0
  attr :gift_value, :string, default: "0"
  attr :observation, :any, default: nil
  attr :input_error, :string, default: nil
  attr :preview_event, :string, default: nil

  def content(assigns) do
    copy = get_in(assigns.page, ["editions", assigns.locale]) || %{}
    display = assigns.page["display"] || %{}
    stages = assigns.page["stages"] || []

    normalized =
      Enum.map(stages, fn stage ->
        %{
          id: stage["id"],
          target_minor: stage["target_minor"],
          buckets:
            Enum.map(stage["buckets"] || [], fn bucket ->
              %{id: bucket["id"], amount_minor: bucket["amount_minor"]}
            end)
        }
      end)

    projection =
      case PhoenixDonations.Presentation.project(
             assigns.observation,
             assigns.gift_minor,
             normalized,
             currency: "CAD",
             threshold_percent: display["remaining_threshold_percent"] || 50,
             remaining_enabled: Map.get(display, "show_remaining_above", true)
           ) do
        {:ok, result} -> result
        {:error, _} -> nil
      end

    active = projection && Enum.find(stages, &(&1["id"] == projection.active_stage_id))

    rows =
      if projection,
        do: cards(projection, stages, active, copy, assigns.locale, assigns.gift_minor),
        else: []

    assigns =
      assign(assigns,
        copy: copy,
        projection: projection,
        active_stage: active,
        cards: rows,
        card_json: Jason.encode!(rows),
        prefix: if(assigns.preview_mode, do: "donation-cms-preview", else: "donation"),
        campaign_url: safe_url(get_in(assigns.page, ["links", "campaign"])),
        brochure_url: safe_url(get_in(assigns.page, ["links", "brochure"]))
      )

    ~H"""
    <section
      id={if @preview_mode, do: "donation-cms-preview", else: "donate-page"}
      class="donation-authored mx-auto max-w-5xl px-5 py-10"
    >
      <h1 class="font-heading text-4xl text-stone-950 sm:text-5xl">{text(@copy, "title")}</h1>
      <p
        :if={present?(@copy, "lead")}
        class="mt-5 max-w-4xl whitespace-pre-line text-xl leading-8 text-stone-700"
      >
        {text(@copy, "lead")}
      </p>
      <section id={"#{@prefix}-campaign"} class="mt-7 space-y-3">
        <h2 :if={present?(@copy, "campaign_heading")} class="font-heading text-2xl">
          {text(@copy, "campaign_heading")}
        </h2>
        <p :if={present?(@copy, "campaign_body")} class="whitespace-pre-line leading-7 text-stone-700">
          {text(@copy, "campaign_body")}
        </p>
      </section>
      <section
        class="mt-7 rounded-xl border border-stone-200 bg-white p-4 sm:p-6"
        aria-labelledby={
          if present?(@copy, heading(@projection)), do: "#{@prefix}-allocation-heading"
        }
      >
        <h2
          :if={present?(@copy, heading(@projection))}
          id={"#{@prefix}-allocation-heading"}
          class="font-heading text-2xl"
        >
          {text(@copy, heading(@projection))}
        </h2>
        <p :if={present?(@copy, note(@projection))} class="mt-2 whitespace-pre-line text-stone-700">
          {text(@copy, note(@projection))}
        </p>
        <p
          :if={!@projection || !@projection.baseline_known?}
          id={"#{@prefix}-funding-unknown"}
          class="mt-3 text-sm font-semibold text-stone-700"
        >
          {text(@copy, "funding_unknown")}
        </p>
        <p id={"#{@prefix}-projection-note"} class="mt-2 text-sm text-stone-600">
          {text(@copy, "projection_note")}
        </p>
        <div class="donation-budget-layout mt-5">
          <div class="donation-budget-column">
            <div
              id={"#{@prefix}-buckets"}
              phx-hook=".BucketProjection"
              phx-update="ignore"
              data-cards={@card_json}
              class="donation-bucket-stack"
            >
              <article
                :for={card <- @cards}
                data-key={card.key}
                data-kind={card.kind}
                class={"donation-bucket-card #{if card.full, do: "is-complete", else: "is-current"} #{card.kind}"}
              >
                <h3>{card.label}</h3>
                <div
                  class="donation-bucket-vessel"
                  role={if card.numeric, do: "progressbar"}
                  aria-hidden={if !card.numeric, do: "true"}
                  aria-label={card.aria_label}
                  aria-valuemin={if card.numeric, do: 0}
                  aria-valuemax={if card.numeric, do: card.goal_minor / 100}
                  aria-valuenow={if card.numeric, do: card.allocated_minor / 100}
                  aria-valuetext={if card.numeric, do: card.primary <> " " <> card.secondary}
                >
                  <div class="donation-bucket-fill" style={"height:#{card.level}%"}></div>
                </div>
                <p class="donation-bucket-primary">{card.primary}</p>
                <p class="donation-bucket-secondary">{card.secondary}</p>
              </article>
            </div>
            <p
              :if={@projection && @projection.complete?}
              id={"#{@prefix}-complete"}
              role="status"
              class="mt-4 font-semibold"
            >
              {text(@copy, "complete_note")}
            </p>
            <p
              :if={@active_stage && present?(@copy, "budget_label")}
              class="mt-4 text-sm text-stone-600"
            >
              {text(@copy, "budget_label")}: {money(@active_stage["target_minor"], @locale)}
            </p>
          </div>
          <aside class="donation-gift-controls">
            <form
              :if={!@preview_mode or is_binary(@preview_event)}
              id={"#{@prefix}-gift-form"}
              phx-change={@preview_event || "preview_gift"}
              phx-submit={@preview_event || "preview_gift"}
            >
              <.gift_input
                copy={@copy}
                prefix={@prefix}
                value={@gift_value}
                disabled={false}
                error={@input_error}
              />
            </form>
            <div :if={@preview_mode and is_nil(@preview_event)}>
              <.gift_input
                copy={@copy}
                prefix={@prefix}
                value={@gift_value}
                disabled={true}
              />
            </div>
            <div class="mt-4 flex flex-col items-start gap-3">
              <a
                :if={@campaign_url && present?(@copy, "cta_label")}
                id={if @preview_mode, do: "donation-cms-preview-cta", else: "manifund-donate"}
                href={if !@preview_mode, do: @campaign_url}
                phx-hook={if !@preview_mode, do: "PauseAiCaWeb.Layouts.TrackOutbound"}
                data-donation={if !@preview_mode, do: "manifund"}
                target={if !@preview_mode, do: "_blank"}
                rel={if !@preview_mode, do: "noopener noreferrer"}
                aria-disabled={if @preview_mode, do: "true"}
                class="inline-block rounded-lg bg-brand px-5 py-3 font-semibold text-stone-950 hover:bg-brand-strong"
              >
                {text(@copy, "cta_label")}
                <span aria-hidden="true">↗</span><span :if={!@preview_mode} class="sr-only">{gettext(
                  "Opens in a new tab"
                )}</span>
              </a>
              <a
                :if={@brochure_url && present?(@copy, "brochure_label")}
                id={if @preview_mode, do: "donation-cms-preview-brochure", else: "donation-brochure"}
                href={if !@preview_mode, do: @brochure_url}
                phx-hook={if !@preview_mode, do: "PauseAiCaWeb.Layouts.TrackOutbound"}
                data-donation={if !@preview_mode, do: "brochure"}
                target={if !@preview_mode, do: "_blank"}
                rel={if !@preview_mode, do: "noopener noreferrer"}
                aria-disabled={if @preview_mode, do: "true"}
                class="font-semibold underline underline-offset-4"
              >{text(@copy, "brochure_label")}
              <span aria-hidden="true">↗</span><span :if={!@preview_mode} class="sr-only">{gettext(
                "Opens in a new tab"
              )}</span></a>
            </div>
            <p
              :if={@campaign_url && present?(@copy, "account_requirement")}
              id={
                if @preview_mode,
                  do: "donation-cms-preview-account-note",
                  else: "manifund-account-requirement"
              }
              class="mt-3 whitespace-pre-line text-sm leading-6 text-stone-700"
            >
              {text(@copy, "account_requirement")}
            </p>
            <p :if={@campaign_url && present?(@copy, "proposal_label")} class="mt-2 text-sm">
              <a
                id={if @preview_mode, do: "donation-cms-preview-proposal", else: "manifund-proposal"}
                href={if !@preview_mode, do: @campaign_url}
                aria-disabled={if @preview_mode, do: "true"}
                class="underline underline-offset-4"
              >{text(@copy, "proposal_label")}</a>
            </p>
            <p :if={!@campaign_url && present?(@copy, "unavailable_note")} class="mt-3 text-sm">
              {text(@copy, "unavailable_note")}
            </p>
          </aside>
        </div>
      </section>
      <section id="donate-interac" class="mt-8 border-l-4 border-brand bg-brand-wash p-5 sm:p-6">
        <h2 :if={present?(@copy, "interac_heading")} class="font-heading text-2xl">
          {text(@copy, "interac_heading")}
        </h2>
        <p :if={present?(@copy, "interac_body")} class="mt-3 whitespace-pre-line leading-7">
          {text(@copy, "interac_body")}
        </p>
        <p class="mt-3 break-all font-semibold">
          <span
            id={if @preview_mode, do: "donation-cms-preview-email", else: "donation-email"}
            class="select-all"
          >pauseaicanada@proton.me</span>
        </p>
        <p class="mt-2">{text(@copy, "recipient_label")}: <strong>PauseAI Canada</strong></p>
      </section>
      <p class="mt-8 text-sm text-stone-600">
        {gettext("PauseAI Canada")} · {gettext("Corporation number")}: 1819452-1 · {gettext(
          "Business Number"
        )}: 791107246
      </p>
      <style>
        .donation-budget-layout{display:grid;grid-template-columns:minmax(0,1fr) 280px;gap:26px;align-items:start}.donation-bucket-stack{display:flex;flex-direction:column;gap:10px;overflow-anchor:none}.donation-bucket-card{display:grid;grid-template-columns:48px minmax(0,1fr);gap:3px 12px;border:1px solid #d6d3d1;border-radius:12px;padding:13px;overflow:hidden}.donation-bucket-card.is-current{border:2px solid var(--color-brand,#f97316)}.donation-bucket-card.is-complete{background:var(--color-brand-wash,#fff7ed)}.donation-bucket-card h3{grid-column:2;grid-row:1;font-size:16px;font-weight:650;line-height:1.35}.donation-bucket-vessel{grid-column:1;grid-row:1 / 4;align-self:center;position:relative;width:42px;height:58px;border:2px solid #a8a29e;border-top:0;border-radius:0 0 11px 11px;background:#fafaf9;overflow:hidden}.donation-bucket-fill{position:absolute;bottom:0;left:0;right:0;background:var(--color-brand,#f97316);transition:height 550ms cubic-bezier(.22,.61,.36,1)}.donation-bucket-primary{grid-column:2;font-weight:700;font-size:17px;line-height:1.3;margin:2px 0}.donation-bucket-secondary{grid-column:2;font-size:12px;line-height:1.4;color:#57534e;overflow-wrap:anywhere}.donation-bucket-card.stage{background:#fafaf9}.donation-bucket-card.stage h3{font-size:17px}.donation-gift-controls{border-left:1px solid #e7e5e4;padding-left:23px;min-width:0}.donation-authored p,.donation-authored h1,.donation-authored h3,.donation-authored a{overflow-wrap:anywhere}.donation-authored a{max-width:100%}@media(max-width:700px){.donation-budget-layout{grid-template-columns:1fr;gap:18px}.donation-gift-controls{grid-row:1;border-left:0;border-bottom:1px solid #e7e5e4;padding:0 0 18px}.donation-budget-column{grid-row:2}.donation-bucket-card{padding:11px;grid-template-columns:42px minmax(0,1fr);gap:3px 10px}.donation-bucket-vessel{width:38px;height:54px}}@media(prefers-reduced-motion:reduce){.donation-bucket-fill{transition:none!important}.donation-bucket-card{animation:none!important}}
      </style>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".BucketProjection">
        export default {
          mounted(){this.revision=0;this.motion=matchMedia('(prefers-reduced-motion: reduce)');this.onMotion=()=>{if(this.motion.matches)this.el.querySelectorAll('.donation-bucket-card').forEach(card=>card.getAnimations().forEach(a=>a.finish()));this.renderCards()};this.motion.addEventListener('change',this.onMotion)},
          updated(){this.renderCards()},
          destroyed(){this.motion.removeEventListener('change',this.onMotion)},
          renderCards(){
            const rows=JSON.parse(this.el.dataset.cards||'[]'),revision=++this.revision;
            const existing=new Map([...this.el.querySelectorAll('.donation-bucket-card')].map(card=>[card.dataset.key,card]));
            const wanted=new Set(rows.map(row=>row.key));
            [...existing.values()].filter(card=>!wanted.has(card.dataset.key)).reverse().forEach((card,index)=>{
              if(this.motion.matches){card.remove();return}if(card.dataset.exiting)return;
              card.dataset.exiting='true';card.setAttribute('aria-hidden','true');card.getAnimations().forEach(a=>a.cancel());
              const style=getComputedStyle(card),height=card.getBoundingClientRect().height;
              card.animate([{height:height+'px',opacity:1,paddingTop:style.paddingTop,paddingBottom:style.paddingBottom,borderWidth:style.borderWidth},{height:'0px',opacity:0,paddingTop:'0px',paddingBottom:'0px',borderWidth:'0px'}],{duration:280,delay:Math.min(index*55,220),easing:'ease-in-out',fill:'forwards'}).finished.then(()=>{if(card.dataset.exiting)card.remove()}).catch(()=>{});
            });
            rows.forEach((row,index)=>{
              let card=existing.get(row.key),fresh=!card;
              if(fresh){card=document.createElement('article');card.dataset.key=row.key;card.innerHTML='<h3></h3><div class="donation-bucket-vessel"><div class="donation-bucket-fill" style="height:0%"></div></div><p class="donation-bucket-primary"></p><p class="donation-bucket-secondary"></p>';this.el.append(card)}
              else if(card.dataset.exiting){card.getAnimations().forEach(a=>a.cancel());delete card.dataset.exiting;card.removeAttribute('aria-hidden')}
              this.el.append(card);card.dataset.kind=row.kind;
              card.className='donation-bucket-card '+(row.full?'is-complete':'is-current')+' '+row.kind;
              card.querySelector('h3').textContent=row.label;card.querySelector('.donation-bucket-primary').textContent=row.primary;card.querySelector('.donation-bucket-secondary').textContent=row.secondary;
              const vessel=card.querySelector('.donation-bucket-vessel');vessel.setAttribute('aria-label',row.aria_label);
              if(row.numeric){vessel.removeAttribute('aria-hidden');vessel.setAttribute('role','progressbar');vessel.setAttribute('aria-valuemin','0');vessel.setAttribute('aria-valuemax',row.goal_minor/100);vessel.setAttribute('aria-valuenow',row.allocated_minor/100);vessel.setAttribute('aria-valuetext',row.primary+' '+row.secondary)}else{vessel.setAttribute('aria-hidden','true');['role','aria-valuemin','aria-valuemax','aria-valuenow','aria-valuetext'].forEach(key=>vessel.removeAttribute(key))}
              const level=card.querySelector('.donation-bucket-fill'),delay=this.motion.matches?0:Math.min(index*90,360);level.style.transitionDelay=fresh?delay+'ms':'0ms';
              const fill=()=>{if(revision===this.revision&&!card.dataset.exiting)level.style.height=row.level+'%'};
              if(fresh&&!this.motion.matches){const style=getComputedStyle(card),height=card.getBoundingClientRect().height;card.animate([{height:'0px',opacity:0,transform:'translateY(5px)',paddingTop:'0px',paddingBottom:'0px',borderWidth:'0px'},{height:height+'px',opacity:1,transform:'translateY(0)',paddingTop:style.paddingTop,paddingBottom:style.paddingBottom,borderWidth:style.borderWidth}],{duration:360,delay,easing:'cubic-bezier(.22,.61,.36,1)',fill:'backwards'});requestAnimationFrame(()=>requestAnimationFrame(fill))}else fill();
            });
          }
        }
      </script>
    </section>
    """
  end

  attr :copy, :map, required: true
  attr :prefix, :string, required: true
  attr :value, :string, required: true
  attr :disabled, :boolean, required: true
  attr :error, :string, default: nil

  defp gift_input(assigns) do
    ~H"""
    <label for={"#{@prefix}-gift"} class="block font-semibold">{text(@copy, "gift_label")}</label>
    <input
      id={"#{@prefix}-gift"}
      name="gift[amount]"
      type="number"
      min="0"
      max="999999999.99"
      step="0.01"
      inputmode="decimal"
      value={@value}
      disabled={@disabled}
      aria-invalid={if @error, do: "true"}
      aria-describedby={"#{@prefix}-gift-note #{@prefix}-projection-note"}
      class="mt-2 block w-44 max-w-full rounded-md border border-stone-400 bg-white px-3 py-2"
    />
    <p id={"#{@prefix}-gift-note"} class="mt-2 whitespace-pre-line text-sm text-stone-600">
      {text(@copy, "gift_note")}
    </p>
    <p :if={@error} id={"#{@prefix}-gift-error"} role="alert" class="mt-2 text-sm text-error">
      {@error}
    </p>
    """
  end

  defp cards(project, stages, active, copy, locale, gift) do
    stage_rows =
      Enum.map(project.stage_cards, fn item ->
        stage = Enum.find(stages, &(&1["id"] == item.id))

        row(
          "stage:#{item.id}",
          "stage",
          label(stage, locale),
          item.target_minor,
          item.allocated_minor,
          copy,
          locale,
          project.baseline_known?,
          gift
        )
      end)

    buckets = if active, do: active["buckets"], else: []

    budget_rows =
      Enum.map(project.bucket_cards, fn item ->
        bucket = Enum.find(buckets, &(&1["id"] == item.id))

        row(
          "bucket:#{project.active_stage_id}:#{item.id}",
          "bucket",
          label(bucket, locale),
          item.cost_minor,
          item.allocated_minor,
          copy,
          locale,
          project.baseline_known?,
          gift
        )
      end)

    stage_rows ++ budget_rows
  end

  defp row(key, kind, label, goal, allocated, copy, locale, known, gift) do
    remaining = goal - allocated
    numeric = known || gift > 0

    primary =
      cond do
        !numeric ->
          text(copy, "budget_label") <> ": " <> money(goal, locale)

        remaining == 0 ->
          text(copy, "covered_label")

        true ->
          money(remaining, locale) <>
            " " <>
            text(copy, "remaining_label") <>
            if(gift > 0, do: " " <> text(copy, "after_gift_label"), else: "")
      end

    secondary =
      if numeric,
        do:
          money(allocated, locale) <>
            " " <> text(copy, "toward_label") <> " " <> money(goal, locale),
        else: ""

    %{
      key: key,
      kind: kind,
      label: label,
      primary: primary,
      secondary: secondary,
      numeric: numeric,
      goal_minor: goal,
      allocated_minor: allocated,
      full: remaining == 0,
      level: allocated * 100 / goal,
      aria_label: label <> " — " <> text(copy, "projection_note")
    }
  end

  defp heading(%{mode: :remaining}), do: "remaining_heading"
  defp heading(_), do: "allocation_heading"
  defp note(%{mode: :remaining}), do: "remaining_note"
  defp note(_), do: "allocation_note"
  defp text(copy, key), do: Map.get(copy, key, "")
  defp present?(copy, key), do: String.trim(text(copy, key)) != ""
  defp label(nil, _), do: ""
  defp label(value, "fr"), do: value["label_fr"] || ""
  defp label(value, _), do: value["label_en"] || ""

  @doc "Parse an ephemeral CAD illustration without persistence or floating-point conversion."
  def gift_amount_minor(""), do: {:ok, 0}

  def gift_amount_minor(value) when is_binary(value) do
    if Regex.match?(~r/\A[0-9]{1,9}(?:\.[0-9]{0,2})?\z/, value) do
      case Decimal.parse(value) do
        {amount, ""} -> {:ok, amount |> Decimal.mult(100) |> Decimal.to_integer()}
        _ -> :error
      end
    else
      :error
    end
  end

  def gift_amount_minor(_), do: :error

  def money(minor, locale) do
    whole =
      minor
      |> div(100)
      |> Integer.to_string()
      |> String.replace(~r/\B(?=(\d{3})+(?!\d))/, if(locale == "fr", do: " ", else: ","))

    cents = rem(minor, 100)

    number =
      whole <>
        if(cents == 0,
          do: "",
          else:
            if(locale == "fr", do: ",", else: ".") <>
              String.pad_leading(Integer.to_string(cents), 2, "0")
        )

    if locale == "fr", do: number <> " $ CA", else: "C$" <> number
  end

  defp safe_url(value) when is_binary(value) do
    case URI.parse(value) do
      %URI{scheme: "https", host: host, userinfo: nil} when is_binary(host) and host != "" ->
        value

      _ ->
        nil
    end
  end

  defp safe_url(_), do: nil
end
