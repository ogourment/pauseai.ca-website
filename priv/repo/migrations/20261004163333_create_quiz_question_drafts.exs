defmodule PauseAiCa.Repo.Migrations.CreateQuizQuestionDrafts do
  use Ecto.Migration

  def up do
    create table(:quiz_question_drafts, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :review_id, :text, null: false
      add :concept_id, :text, null: false
      add :topic, :text, null: false, default: "actions"
      add :kind, :text, null: false, default: "factual"
      add :status, :text, null: false, default: "draft"
      add :editions, :map, null: false, default: %{}
      add :revision, :integer, null: false, default: 1
      add :updated_by, references(:users, type: :uuid, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:quiz_question_drafts, [:review_id])
    create unique_index(:quiz_question_drafts, [:concept_id])
    create constraint(:quiz_question_drafts, :draft_only, check: "status = 'draft'")

    create table(:quiz_question_revisions) do
      add :question_id, references(:quiz_question_drafts, type: :uuid, on_delete: :delete_all),
        null: false

      add :revision, :integer, null: false
      add :editor_id, references(:users, type: :uuid, on_delete: :nilify_all)
      add :editions, :map, null: false
      add :kind, :text, null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:quiz_question_revisions, [:question_id, :revision])

    if Application.get_env(:pauseai_ca, :mail_environment) in [:dev, :test, :staging],
      do:
        execute(
          "INSERT INTO quiz_question_drafts (id, review_id, concept_id, topic, kind, editions, inserted_at, updated_at) VALUES (gen_random_uuid(), 'LEARN-ACT-Q-01', 'mp-effectiveness', 'politics', 'discussion', '{\"en\": {\"question\": \"How useful can talking to your MP be?\", \"answer\": \"A conversation can put a specific request before your constituency’s representative and open a follow-up. Its outcome depends on the context and what happens afterward. Which result would you seek: an answer, a meeting, a stated position or a parliamentary step?\", \"options\": [], \"source\": \"House of Commons · MPs’ role; PauseAI action proposal\", \"url\": \"https://www.ourcommons.ca/en/members\", \"correct\": null, \"action\": \"Find your MP; choose a request and prepare a meeting with others.\", \"notes\": \"\"}, \"fr\": {\"question\": \"Parler à votre député peut-il vraiment être utile?\", \"answer\": \"Un échange peut faire connaître une demande précise à la personne qui représente votre circonscription et ouvrir un suivi. Le résultat dépend du contexte et des suites données. Quel résultat chercheriez-vous : une réponse à une question, une rencontre, une prise de position ou une démarche parlementaire?\", \"options\": [], \"source\": \"Chambre des communes · rôle des députés; proposition d’action PauseIA\", \"url\": \"https://www.noscommunes.ca/fr/deputes\", \"correct\": null, \"action\": \"Trouver votre député; choisir une demande et préparer une rencontre avec d’autres.\", \"notes\": \"\"}}'::jsonb, now(), now())"
        )

    if Application.get_env(:pauseai_ca, :mail_environment) in [:dev, :test, :staging],
      do:
        execute(
          "INSERT INTO quiz_question_drafts (id, review_id, concept_id, topic, kind, editions, inserted_at, updated_at) VALUES (gen_random_uuid(), 'LEARN-ACT-Q-02', 'petition-outcome', 'politics', 'factual', '{\"en\": {\"question\": \"What must the government do when a petition is presented to the House of Commons?\", \"options\": [\"Adopt the requested policy\", \"Provide a formal response\", \"Meet every signatory\"], \"answer\": \"The government responds within 45 calendar days, or the next sitting day if the House is not sitting. The obligation is to respond; it does not promise adoption of the request.\", \"source\": \"House of Commons · petitions\", \"url\": \"https://www.ourcommons.ca/petitions/en/home/index\", \"correct\": 1, \"action\": \"Choose a petition, read its request and follow the government’s response.\", \"notes\": \"\"}, \"fr\": {\"question\": \"Une pétition présentée à la Chambre des communes oblige le gouvernement à faire quoi?\", \"options\": [\"Adopter la mesure demandée\", \"Fournir une réponse officielle\", \"Organiser une rencontre avec chaque signataire\"], \"answer\": \"Le gouvernement doit répondre dans les 45 jours civils, ou le jour de séance suivant si la Chambre ne siège pas. Cette obligation porte sur une réponse; elle ne promet pas l’adoption de la demande.\", \"source\": \"Chambre des communes · pétitions\", \"url\": \"https://www.noscommunes.ca/petitions/fr/Home/Index\", \"correct\": 1, \"action\": \"Choisir une pétition, lire sa demande et suivre la réponse du gouvernement.\", \"notes\": \"\"}}'::jsonb, now(), now())"
        )

    if Application.get_env(:pauseai_ca, :mail_environment) in [:dev, :test, :staging],
      do:
        execute(
          "INSERT INTO quiz_question_drafts (id, review_id, concept_id, topic, kind, editions, inserted_at, updated_at) VALUES (gen_random_uuid(), 'LEARN-ACT-Q-03', 'petition-route', 'politics', 'factual', '{\"en\": {\"question\": \"When an official e-petition closes, how many valid signatures are required for certification?\", \"options\": [\"25\", \"250\", \"500\"], \"answer\": \"An official e-petition requires at least 500 valid signatures for certification. The paper-petition threshold is 25. Certification and presentation by an MP are separate steps.\", \"source\": \"House of Commons · sponsors’ guide\", \"url\": \"https://www.ourcommons.ca/petitions/en/Home/AboutContent?guide=PIGuideForMP\", \"correct\": 2, \"action\": \"Form a small team, prepare a request and seek an MP sponsor.\", \"notes\": \"\"}, \"fr\": {\"question\": \"Vous lancez une pétition électronique officielle. Quel seuil de signatures valides permet sa certification, à la fermeture?\", \"options\": [\"25\", \"250\", \"500\"], \"answer\": \"Une pétition électronique officielle nécessite au moins 500 signatures valides pour la certification. La pétition papier a un seuil de 25. La certification et la présentation par un député sont des étapes distinctes.\", \"source\": \"Chambre des communes · guide des députés parrains\", \"url\": \"https://www.noscommunes.ca/petitions/fr/Home/AboutContent?guide=PIGuideForMP\", \"correct\": 2, \"action\": \"Former une petite équipe, préparer une demande et chercher un député parrain.\", \"notes\": \"\"}}'::jsonb, now(), now())"
        )

    if Application.get_env(:pauseai_ca, :mail_environment) in [:dev, :test, :staging],
      do:
        execute(
          "INSERT INTO quiz_question_drafts (id, review_id, concept_id, topic, kind, editions, inserted_at, updated_at) VALUES (gen_random_uuid(), 'LEARN-ACT-Q-04', 'meeting-goal', 'treaty', 'planning', '{\"en\": {\"question\": \"You have 20 minutes with your MP. Which goal would you choose for this first meeting?\", \"options\": [\"Make a specific request and agree on follow-up\", \"Explain as many risks as possible\", \"Seek an immediate public commitment\"], \"answer\": \"PauseAI proposal: bring a specific request, sources and a question about the next step. Other goals may be useful depending on the person and context. Discuss your choice with the group.\", \"source\": \"PauseAI · organizing proposal for review\", \"url\": \"https://pauseai.ca/en/strategy\", \"correct\": null, \"action\": \"Prepare a request, share roles and invite others from the constituency.\", \"notes\": \"\"}, \"fr\": {\"question\": \"Vous obtenez 20 minutes avec votre député. Quel objectif choisiriez-vous pour cette première rencontre?\", \"options\": [\"Poser une demande précise et convenir d’un suivi\", \"Présenter le plus de risques possible\", \"Demander un engagement public immédiat\"], \"answer\": \"Proposition PauseIA : arrivez avec une demande précise, des sources et une question sur la prochaine étape. Les autres objectifs peuvent être utiles selon la personne et le contexte. Discutez de votre choix avec le groupe.\", \"source\": \"PauseIA · proposition d’organisation à revoir\", \"url\": \"https://pauseia.ca/fr/strategie\", \"correct\": null, \"action\": \"Préparer une demande, répartir les rôles et inviter d’autres personnes de la circonscription.\", \"notes\": \"\"}}'::jsonb, now(), now())"
        )

    if Application.get_env(:pauseai_ca, :mail_environment) in [:dev, :test, :staging],
      do:
        execute(
          "INSERT INTO quiz_question_drafts (id, review_id, concept_id, topic, kind, editions, inserted_at, updated_at) VALUES (gen_random_uuid(), 'LEARN-ACT-Q-05', 'meeting-follow-up', 'treaty', 'planning', '{\"en\": {\"question\": \"Your MP replies, “We’ll look into it.” What could you do next?\", \"options\": [\"Record the request as accepted\", \"Ask what happens next and when to follow up\", \"Immediately announce that the MP supports the proposal\"], \"answer\": \"PauseAI proposal: ask for a next step and a follow-up time. Retain the exact reply; an undertaking to consider something is not a statement of support.\", \"source\": \"PauseAI · organizing proposal for review\", \"url\": \"https://pauseai.ca/en/strategy\", \"correct\": null, \"action\": \"Record the reply, assign follow-up and prepare the next action together.\", \"notes\": \"\"}, \"fr\": {\"question\": \"Votre député vous répond : « Nous allons examiner la question. » Que pourriez-vous faire ensuite?\", \"options\": [\"Considérer la demande comme acceptée\", \"Demander quelle étape suivra et quand reprendre contact\", \"Publier immédiatement que le député soutient la proposition\"], \"answer\": \"Proposition PauseIA : demander une prochaine étape et un moment de suivi. Conservez les mots exacts de la réponse; une promesse d’examiner une question ne constitue pas une prise de position favorable.\", \"source\": \"PauseIA · proposition d’organisation à revoir\", \"url\": \"https://pauseia.ca/fr/strategie\", \"correct\": null, \"action\": \"Noter la réponse, confier le suivi à une personne et préparer la prochaine action ensemble.\", \"notes\": \"\"}}'::jsonb, now(), now())"
        )

    if Application.get_env(:pauseai_ca, :mail_environment) in [:dev, :test, :staging],
      do:
        execute(
          "INSERT INTO quiz_question_drafts (id, review_id, concept_id, topic, kind, editions, inserted_at, updated_at) VALUES (gen_random_uuid(), 'LEARN-ACT-Q-06', 'start-incubator', 'treaty', 'discussion', '{\"en\": {\"question\": \"After your first MP meeting, what would you like to organize with the others?\", \"options\": [], \"answer\": \"Choose the next goal together: study an unanswered question, follow up a reply, prepare another meeting or propose a local incubator. Begin with interested people and a concrete responsibility.\", \"source\": \"PauseAI · proposed local-incubator path\", \"url\": \"https://pauseai.ca/en/strategy\", \"correct\": null, \"action\": \"Set another gathering and join or start an incubator.\", \"notes\": \"\"}, \"fr\": {\"question\": \"Après une première rencontre avec votre député, qu’aimeriez-vous organiser avec les autres?\", \"options\": [], \"answer\": \"Choisissez un prochain objectif ensemble : étudier une question restée ouverte, suivre une réponse, préparer une autre rencontre ou proposer un incubateur local. Commencez par les personnes intéressées et une responsabilité concrète.\", \"source\": \"PauseIA · parcours vers les incubateurs locaux, proposition\", \"url\": \"https://pauseia.ca/fr/strategie\", \"correct\": null, \"action\": \"Proposer un prochain rendez-vous et rejoindre ou démarrer un incubateur.\", \"notes\": \"\"}}'::jsonb, now(), now())"
        )
  end

  def down do
    drop table(:quiz_question_revisions)
    drop table(:quiz_question_drafts)
  end
end
