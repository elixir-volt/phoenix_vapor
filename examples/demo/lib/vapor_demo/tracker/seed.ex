defmodule VaporDemo.Tracker.Seed do
  @moduledoc "The tracker's state as the demo starts: two teams, five people, their issues."

  @people [
    {"Alice Chen", "AC", "#6E7BFF"},
    {"Bob Smith", "BS", "#F5A524"},
    {"Carol Davis", "CD", "#3DD68C"},
    {"Dave Wilson", "DW", "#E879A6"},
    {"Eve Johnson", "EJ", "#4C9BFF"}
  ]

  @teams [
    %{key: "engineering", name: "Engineering", prefix: "ENG"},
    %{key: "design", name: "Design", prefix: "DES"}
  ]

  # {team, number, title, status, priority, assignee, labels, description}
  @issues [
    {"engineering", 151, "Rate-limit the public search endpoint", "backlog", "low", 4, ["API"],
     "Search is open to anonymous clients. Allow 60 requests a minute per IP, and answer 429 with Retry-After beyond that."},
    {"engineering", 150, "Export issues as CSV", "backlog", "none", nil, ["API"], ""},
    {"engineering", 149, "Dark mode for the settings pages", "backlog", "low", 3, ["UI"],
     "Settings still use the light palette in dark mode."},
    {"engineering", 147, "Keyboard shortcuts for moving issues between columns", "todo", "medium",
     1, ["UI"], "Shift and the arrow keys move the focused card one column left or right."},
    {"engineering", 146, "Invite links expire after seven days", "todo", "medium", 5, ["Auth"],
     "Invites never expire today. Store an expiry with the token and show a clear message on an expired link."},
    {"engineering", 145, "Retry webhooks with backoff", "todo", "high", 4, ["API"],
     "A failed delivery is dropped. Retry five times, doubling the delay from 30 seconds."},
    {"engineering", 143, "Show who else is viewing an issue", "todo", "low", 2, ["Realtime"],
     "Presence on the issue page, from Phoenix.Presence."},
    {"engineering", 142, "Fix login redirect after the session expires", "in_progress", "urgent",
     1, ["Bug", "Auth"],
     "When a session expires on a page other than the dashboard, signing in again lands on the dashboard instead of the page the user was on.\n\nKeep the path in the session before redirecting to sign-in, and return to it after."},
    {"engineering", 139, "Bulk-edit labels from the issue list", "in_progress", "medium", 3,
     ["UI"], "Select issues in the list and add or remove a label for all of them."},
    {"engineering", 138, "Paginate the activity API", "in_review", "medium", 4, ["API"],
     "Cursor pagination, 50 entries a page."},
    {"engineering", 137, "Activity feed updates without a reload", "done", "medium", 5,
     ["Realtime"], ""},
    {"engineering", 131, "Paginate the members API", "done", "low", 4, ["API"], ""},
    {"engineering", 128, "Upgrade to Phoenix 1.8", "done", "high", 1, [], ""},
    {"design", 64, "Empty states for the board", "todo", "medium", 2, ["UI"],
     "A column with no issues shows nothing. Give it a short line and a way to add one."},
    {"design", 63, "Priority icons at 12px", "in_progress", "low", 2, ["UI"],
     "The bars blur at small sizes; draw them on the pixel grid."},
    {"design", 61, "Onboarding checklist", "backlog", "none", nil, [], ""},
    {"design", 60, "Command palette layout", "in_review", "high", 2, ["UI"],
     "Group results by kind, with the shortcut on the right."},
    {"design", 58, "Light theme contrast pass", "done", "medium", 3, ["UI"], ""}
  ]

  @comments [
    {"ENG-142", 3, "Reproduced on the settings page. The redirect drops query params too.",
     1_200},
    {"ENG-142", 1, "On it. I'll keep the full URL, params included.", 300},
    {"ENG-145", 4, "Should failed deliveries show up in the activity feed?", 5_400}
  ]

  @activity [
    {1, "moved ENG-142 to In Progress", 60},
    {5, "closed ENG-137", 240},
    {3, "commented on ENG-139", 720},
    {2, "created DES-64", 3_600},
    {4, "set the priority of ENG-151", 7_200}
  ]

  @doc "The seeded state."
  def state do
    now = System.system_time(:second)

    people =
      for {{name, initials, color}, id} <- Enum.with_index(@people, 1),
          do: %{id: id, name: name, initials: initials, color: color}

    issues =
      for {{team, number, title, status, priority, assignee, labels, description}, id} <-
            Enum.with_index(@issues, 1) do
        prefix = Enum.find(@teams, &(&1.key == team)).prefix

        %{
          id: id,
          team: team,
          number: number,
          key: "#{prefix}-#{number}",
          title: title,
          description: description,
          status: status,
          priority: priority,
          assignee_id: assignee,
          labels: labels,
          updated_at: now - id * 600
        }
      end

    comments =
      for {{key, author, body, ago}, id} <- Enum.with_index(@comments, 1) do
        issue = Enum.find(issues, &(&1.key == key))
        %{id: id, issue_id: issue.id, author_id: author, body: body, at: now - ago}
      end

    activity =
      for {{person, what, ago}, id} <- Enum.with_index(@activity, 1),
          do: %{id: id, person_id: person, what: what, at: now - ago}

    %{people: people, teams: @teams, issues: issues, comments: comments, activity: activity}
  end
end
