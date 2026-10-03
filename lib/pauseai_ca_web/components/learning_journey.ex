defmodule PauseAiCaWeb.LearningJourney do
  use PauseAiCaWeb, :html
  attr :locale, :string, required: true
  attr :current_scope, :any, default: nil
  attr :quiz, :boolean, default: false

  def journey(assigns) do
    assigns = assign(assigns, :nuggets, PauseAiCa.Learning.nuggets(assigns.locale))

    ~H"""
    <section
      id={if(@quiz, do: "questions", else: "knowledge")}
      class="learning-journey mx-auto max-w-5xl px-5 py-14"
      phx-update="ignore"
      data-learning-root
      data-learning-copy={Jason.encode!(learning_copy())}
      data-locale={@locale}
      data-account-id={if(@current_scope, do: @current_scope.user.id, else: "")}
      data-account={
        if(@current_scope, do: Jason.encode!(@current_scope.user.saved_resources), else: "")
      }
    >
      <p class="eyebrow">{gettext("Choose what to explore")}</p>
      <h2 class="mt-3 font-heading text-4xl">
        {if(@quiz,
          do: gettext("What would you like to understand?"),
          else: gettext("Knowledge nuggets")
        )}
      </h2>
      <p class="mt-4 max-w-3xl leading-7">
        {gettext(
          "Explore a question, read the short answer and add what interests you to your learning list."
        )}
      </p>
      <nav aria-label={gettext("Topics")} class="learning-topics mt-6 flex flex-wrap gap-2">
        <span :for={{topic, label} <- topics()} class={"learning-topic topic-#{topic}"}>{label}</span>
      </nav>
      <div class="mt-8 grid gap-5 md:grid-cols-2">
        <article
          :for={n <- @nuggets}
          id={"nugget-#{n["id"]}"}
          class={"learning-card topic-#{n["topic"]} rounded-2xl border bg-white p-6"}
          data-nugget={n["id"]}
          data-nugget-title={n["title"]}
        >
          <span class={"learning-topic topic-#{n["topic"]}"}>{topic_label(n["topic"])}</span>
          <span
            :if={n["id"] in ["bengio-speed", "research-acceleration"]}
            class="learning-topic topic-voices"
          >{gettext("People and quotations")}</span>
          <p class="mt-3 text-sm text-stone-600">{n["evidence"]}</p>
          <h3 class="mt-3 font-heading text-2xl">{if(@quiz, do: n["question"], else: n["title"])}</h3>
          <div
            :if={@quiz && !n["discussion"]}
            class="mt-5 space-y-2"
            role="group"
            aria-label={n["question"]}
          >
            <button
              :for={{option, index} <- Enum.with_index(n["options"])}
              type="button"
              data-quiz-answer={index}
              aria-pressed="false"
              class="learning-answer"
            >{option}</button>
            <button
              type="button"
              data-quiz-answer="unknown"
              aria-pressed="false"
              class="learning-answer"
            >{gettext("I don't know")}</button>
          </div>
          <p
            :if={@quiz && !n["discussion"]}
            data-quiz-feedback
            role="status"
            class="mt-4 font-semibold"
          >
          </p>
          <details class="mt-4" data-explanation open={!@quiz || n["discussion"]}>
            <summary class="cursor-pointer font-semibold underline">
              {if(n["discussion"],
                do: gettext("Explore the STOP question"),
                else: gettext("Read the explanation")
              )}
            </summary>
            <p class="mt-3 leading-7">{n["answer"]}</p>
            <a href={n["url"]} class="mt-3 inline-block underline" rel="noreferrer">{n["source"]}</a>
            <span :if={n["language"] != @locale} class="ml-2 text-sm">({String.upcase(n["language"])})</span>
          </details>
          <button
            type="button"
            data-basket-toggle={n["id"]}
            aria-pressed="false"
            class="mt-5 rounded-full border-2 border-stone-800 px-4 py-2 font-semibold"
          >{gettext("Add to my list")}</button>
        </article>
      </div>
      <section
        id="my-learning-list"
        class="mt-10 rounded-2xl border border-stone-300 bg-white p-6"
        aria-labelledby="learning-list-title"
      >
        <h3 id="learning-list-title" class="font-heading text-3xl">{gettext("My learning list")}</h3>
        <p data-basket-status role="status" class="mt-3"></p>
        <ul data-basket-list class="mt-4 space-y-3"></ul>
        <p data-learning-storage-warning role="status" class="mt-3 text-amber-900 hidden">
          {gettext("Browser storage is unavailable. Your list will last for this page only.")}
        </p>
        <a
          href={if(@locale == "fr", do: "/fr/comprendre#knowledge", else: "/en/learn#knowledge")}
          class="mt-4 inline-block font-semibold underline"
        >{gettext("Explore the library")}</a>
      </section>
      <section class="mt-8 rounded-2xl bg-stone-100 p-6" aria-labelledby="learning-next-title">
        <h3 id="learning-next-title" class="font-heading text-2xl">{gettext("Stay informed")}</h3>
        <p class="mt-3">
          {gettext(
            "Receive news about AI policy and ways to take part. Choose email updates first; location can wait until you want to organize locally."
          )}
        </p>
        <a
          href={if(@locale == "fr", do: "/fr/comprendre#updates", else: "/en/learn#updates")}
          class="mt-4 inline-block rounded-full bg-brand px-5 py-3 font-bold"
        >{gettext("Subscribe")}</a>
        <div data-return-invitation class="mt-6 hidden">
          <h4 class="font-semibold">{gettext("Welcome back")}</h4>
          <p class="mt-2">
            {gettext(
              "Save your learning list across devices and keep a record of your actions with an account."
            )}
          </p>
          <a
            data-learning-register
            href={"/users/register?locale=#{@locale}"}
            class="mt-3 inline-block font-semibold underline"
          >{gettext("Create an account")}</a>
          <button type="button" data-dismiss-return class="ml-4 underline">{gettext("Later")}</button>
        </div>
        <a
          :if={@current_scope}
          href={if(@locale == "fr", do: "/fr/tableau-de-bord", else: "/en/dashboard")}
          class="mt-4 block underline"
        >{gettext("My dashboard")}</a>
        <div class="mt-6 flex flex-wrap gap-5">
          <a
            href={
              if(@locale == "fr",
                do: "/fr/comprendre#local-participation",
                else: "/en/learn#local-participation"
              )
            }
            class="underline"
          >{gettext("Join or start a group")}</a>
          <a
            href={
              if(@locale == "fr",
                do: "/fr/strategie#engagement-ladder",
                else: "/en/strategy#engagement-ladder"
              )
            }
            class="underline"
          >{gettext("Ways to take part")}</a>
          <a href={if(@locale == "fr", do: "/fr/faire-un-don", else: "/en/donate")} class="underline">{gettext(
            "Donate"
          )}</a>
        </div>
      </section>
    </section>
    """
  end

  defp learning_copy do
    %{
      "remove" => gettext("Remove from my list"),
      "add" => gettext("Add to my list"),
      "removeShort" => gettext("Remove"),
      "empty" => gettext("Your list is empty. Add the topics that interest you."),
      "count" => gettext("Topics in your list:"),
      "syncError" =>
        gettext("Saved in this browser. Account synchronization failed; reload to retry."),
      "unknown" => gettext("Here is some context to explore the question."),
      "correct" => gettext("Yes. Read the qualifications and source."),
      "incorrect" => gettext("The first answer matches the explanation. Here is why.")
    }
  end

  defp topics,
    do: [
      {"research", gettext("Research")},
      {"incidents", gettext("Incidents")},
      {"voices", gettext("People and quotations")},
      {"politics", gettext("Politics")},
      {"treaty", gettext("Treaties and action")}
    ]

  defp topic_label(topic), do: topics() |> List.keyfind(topic, 0) |> elem(1)
end
