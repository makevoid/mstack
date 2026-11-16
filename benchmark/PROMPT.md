Build **Tasklane**, a todo-list web application, in this directory. Work through the phases in order. At the end of every phase run the whole spec suite, make it pass, and commit with git.

Never start a web server (no `rackup`, no `puma`, no `rake` task that serves). Everything is verified with rack-test.

## Stack (fixed)

- Ruby, **Roda** for routing, **Sequel** with **SQLite** for persistence, **HAML** views, **Tailwind CSS** from the CDN script (`https://cdn.tailwindcss.com`) in the layout.
- **RSpec** with **rack-test** for every route, plus model specs. A `Gemfile` listing everything, including `rspec` and `rack-test`.
- `config.ru` must `run` the app. `Rack::Builder.parse_file("config.ru")` is how it will be loaded.
- The database comes from `ENV["DATABASE_URL"]` (a Sequel URL). Default: `sqlite://db/tasklane_<RACK_ENV>.sqlite3`, with `RACK_ENV` defaulting to `development`.
- Migrations live in `db/migrations/` and `rake db:migrate` applies them to whatever `DATABASE_URL` points at.
- Layout: `app.rb` (or `app/`), `models/`, `views/`, `db/migrations/`, `spec/`. Keep route blocks thin; rules live in models or small plain Ruby objects.

## Domain rules (these are the product; get them exactly right)

**Lists**
- A list has a `name` (1 to 60 characters after stripping) and a unique `slug`.
- The slug is derived from the name: lowercase, every run of non-alphanumeric characters becomes one `-`, leading and trailing `-` removed, truncated to 40 characters. A name with no alphanumerics gets the slug `list`.
- A duplicate slug gets a numeric suffix: `groceries`, then `groceries-2`, then `groceries-3`.

**Todos**
- A todo belongs to a list and has a `title` (1 to 120 characters after stripping), a `priority`, an optional `due_on` date (ISO `YYYY-MM-DD`), a `done` flag and `tags`.
- Priority is exactly one of `low`, `normal`, `urgent`. Default `normal`. Anything else is a validation error. There is no `high`.
- A todo is **overdue** when it has a `due_on` earlier than today and is not done.
- Listing order everywhere: `urgent` first, then `normal`, then `low`. Within one priority, by `due_on` ascending with todos that have no due date last. Ties by id ascending.

**Tags**
- Many-to-many between todos and tags. Tag names are stripped and lowercased, 1 to 20 characters, deduplicated per todo.
- At most **5** tags on a todo. A sixth is a validation error, not a silent truncation.
- In HTML forms tags arrive as one comma-separated string. In the JSON API they are an array of strings.

**Soft delete**
- Deleting a todo sets `deleted_at`. Nothing is ever hard-deleted.
- Deleted todos disappear from every list, count, filter and search. They appear only in the trash, and can be restored.

**Counts**
- A list's `open_count` is the number of its todos that are not done and not deleted.

## HTML routes

Every HTML page uses one layout, and its footer contains exactly the text `Tasklane · built with mstack`. All user-supplied text is HTML-escaped.

| Route | Behavior |
|---|---|
| `GET /` | Redirects to `/lists` |
| `GET /lists` | Every list with its name, a link to it and its open count. A form to create a list |
| `POST /lists` | Param `name`. Creates and redirects to `/lists/<slug>`. On a validation error, re-renders with status 422 and the error message |
| `GET /lists/<slug>` | The list's todos. 404 page for an unknown slug. Filters below. A form to add a todo. Each todo shows title, priority, due date, tags, an "overdue" marker when overdue, and toggle and delete buttons |
| `POST /lists/<slug>/todos` | Params `title`, `priority`, `due_on`, `tags`. Creates and redirects to the list. On a validation error, re-renders the list page with status 422 and the messages |
| `POST /todos/<id>/toggle` | Flips `done`, redirects to the todo's list |
| `POST /todos/<id>/delete` | Soft-deletes, redirects to the todo's list |
| `GET /trash` | Deleted todos across all lists, each with a restore button |
| `POST /todos/<id>/restore` | Restores, redirects to `/trash` |
| `GET /healthz` | Plain text `ok:<n>` where n is the number of open (not done, not deleted) todos across all lists |

Filters on `GET /lists/<slug>` (and on the API index), combinable:
- `status`: `open` (default), `done` or `all`.
- `tag`: only todos carrying that tag (case-insensitive).
- `q`: case-insensitive substring match on the title.

## JSON API under `/api/v1`

Requests and responses are JSON. Request bodies are JSON objects.

| Route | Success |
|---|---|
| `GET /api/v1/lists` | 200 `{"lists":[{"slug":..,"name":..,"open_count":..}]}` ordered by name |
| `POST /api/v1/lists` body `{"name":..}` | 201 `{"list":{"slug":..,"name":..,"open_count":0}}` |
| `GET /api/v1/lists/<slug>/todos` | 200 `{"todos":[<todo>...]}` with the filters and the ordering above |
| `POST /api/v1/lists/<slug>/todos` body `{"title":..,"priority":..,"due_on":..,"tags":[..]}` | 201 `{"todo":<todo>}` |
| `PATCH /api/v1/todos/<id>` body with any of `title`, `priority`, `due_on`, `done`, `tags` | 200 `{"todo":<todo>}`. `tags` replaces the whole set |
| `DELETE /api/v1/todos/<id>` | 204, empty body (soft delete) |
| `POST /api/v1/todos/<id>/restore` | 200 `{"todo":<todo>}` |

A `<todo>` is `{"id":..,"title":..,"priority":..,"done":..,"due_on":<"YYYY-MM-DD" or null>,"overdue":..,"tags":[sorted names],"list":<slug>}`.

Errors, always in this shape:
- Unknown list, todo or route under `/api/v1`: 404 `{"error":{"code":"not_found","message":..}}`. A soft-deleted todo is not found for `PATCH` and `DELETE`, and is found for `restore`.
- Validation failure: 422 `{"error":{"code":"validation_failed","message":..,"fields":{"<field>":["<message>",..]}}}`.
- A body that is not a JSON object: 400 `{"error":{"code":"bad_request","message":..}}`.

## Phases

1. **Skeleton.** Gemfile, `config.ru`, database connection, `rake db:migrate`, spec helper with rack-test and a clean database per example, the layout with Tailwind and the footer, `GET /` and `GET /healthz`.
2. **Lists.** Migration, model with slug rules, `GET /lists`, `POST /lists`, `GET /lists/<slug>` (empty for now).
3. **Todos.** Migration, model, validations, priority, ordering, overdue, create and toggle through HTML.
4. **Tags.** Migrations, normalization, the limit of 5, shown on the list page, accepted by the form.
5. **Filters.** `status`, `tag`, `q` on the list page, with links or a small form to drive them.
6. **Soft delete.** Delete, trash, restore, and counts that ignore deleted todos.
7. **JSON API.** Every route in the table, the error shapes, the same rules as the HTML side with no duplicated logic.
8. **Finish.** A `README.md` covering setup, how to run the specs and the domain rules. Run the complete suite one final time and commit.

## When you are done

Reply with: the number of spec examples and failures from the final run, the `git log --oneline` output, and a short list of the design decisions you made that the spec left open, each with its reason.
