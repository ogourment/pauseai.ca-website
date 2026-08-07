defmodule Mix.Tasks.Release.Prepare do
  @shortdoc "Bump the application patch version for the next release"
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, remaining, invalid} = OptionParser.parse(args, strict: [dry_run: :boolean])

    if remaining != [] or invalid != [] do
      Mix.raise("Usage: mix release.prepare [--dry-run]")
    end

    ensure_clean_worktree!()

    path = Path.join(File.cwd!(), "mix.exs")
    source = File.read!(path)
    {version, next_version} = next_patch_version!(source)

    if opts[:dry_run] do
      Mix.shell().info("Next patch release: #{version} → #{next_version}")
    else
      File.write!(
        path,
        String.replace(source, "version: \"#{version}\"", "version: \"#{next_version}\"")
      )

      Mix.shell().info("Bumped application version: #{version} → #{next_version}")
      Mix.shell().info("Now run the checks, commit the version bump, and push main for staging.")
    end
  end

  defp ensure_clean_worktree! do
    {output, 0} = System.cmd("git", ["status", "--porcelain"])

    if output != "" do
      Mix.raise("Commit or stash the current changes before preparing a release.")
    end
  end

  defp next_patch_version!(source) do
    case Regex.run(~r/version: "(\d+)\.(\d+)\.(\d+)"/, source) do
      [_, major, minor, patch] ->
        version = Enum.join([major, minor, patch], ".")

        next_version =
          Enum.join([major, minor, Integer.to_string(String.to_integer(patch) + 1)], ".")

        {version, next_version}

      nil ->
        Mix.raise("Could not find a semantic version in mix.exs.")
    end
  end
end
