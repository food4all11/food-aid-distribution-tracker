# Food Aid Coverage Tracker

A small database and website that record **which HDB block was served, when, by
whom, and how much was left over** — so that duplicated visits and missed blocks
become visible instead of anecdotal.

Built for NH0001 Tech-for-Good Service Learning, scoped to the Bedok planning
area. Designed to be handed to the next group half-finished without breaking.

---

## What's in here

| File | What it is |
|---|---|
| `schema.sql` | The database: 3 tables, 3 derived views, row-level security. Verified against PostgreSQL 16. |
| `wipe_plain.sql` | Empties all three tables, keeping the structure. |
| `simplify_plain.sql` | Drops the surplus view, adds two food-type views. Run once, after schema. |
| `demo_data.js` | Empty. The site starts with no records until you add your own. |
| `index.html` | The whole website. One file. No build step, no framework. |
| `generate_seed.py` | Regenerates both seed files from one definition so they can't drift apart. |

## Starting from empty

The site ships with no records. Every block, organisation and distribution in it
was entered by your team, so anything on screen can be defended in a report.

Order of work:

1. Add your blocks in the Supabase Table Editor (`blocks` table): block number,
   street, planning area, and latitude/longitude from OneMap.
2. Add the organisations you actually work with (`organisations` table).
3. Log distributions through the form on the site, or a linked Google Form.

The map will look sparse at first, with every marker plum for "never recorded".
That is the honest baseline, and it fills in as you log real sessions.

---

## Connecting a real database

### 1. Create the project

Sign up at [supabase.com](https://supabase.com), create a project, and note the
project URL and the `anon` public key from **Project Settings → API**.

The `anon` key is meant to be visible in browser code. It is not a secret. What
protects your data is the row-level security in `schema.sql`, not key secrecy.
Never put the `service_role` key in this file.

### 2. Create the tables

Open the **SQL Editor** in Supabase, paste in `schema.sql`, and run it. Then
paste in `seed_bedok.sql` and run that. You should get 14 rows in `blocks` and
121 in `distributions`.

### 3. Point the website at it

Easiest way: open the site and use the **Connect to your database** panel above
the map. Paste the Project URL and the publishable key, click Connect. It takes
effect immediately and is remembered in that browser.

Once it works, the panel prints the exact two lines to paste into `index.html`
so the setting is permanent for everyone who opens the site. Do that before you
publish, or every visitor will see the connect panel instead of the map.

Note on key names: Supabase now issues short **publishable** keys starting
`sb_publishable_` rather than the old JWT-style `anon` key starting `eyJ`. Both
work and carry the same privileges, so your RLS policies behave identically. The
variable in the file is still called `SUPABASE_ANON_KEY`; leave that name alone
and put the publishable key in it.

### 4. Allow the browser to talk to it

In Supabase, add your site's address under **Authentication → URL Configuration**.
While developing locally, run a server rather than opening the file directly, or
the browser will block the requests:

```bash
python3 -m http.server 8000     # then visit http://localhost:8000
```

### 5. Publish it

Push the folder to a GitHub repo and turn on **Settings → Pages**. You get a
public URL in about a minute, free, with nothing to maintain.

---

## What the website shows

**The coverage strip** across the top is the summary, the legend and the filter
all at once. Each band is sized by how many blocks are in that state. Select one
to filter the map and the list; select it again to clear.

**The map** sizes each marker by how many distributions have been logged there
and colours it by how long since the last one. Blocks with no record at all are
drawn largest and in plum, because absence is the thing this tool exists to make
visible. A cluster of large green markers next to a plum one is the entire
argument of your project in a single image.

**Longest without a distribution** ranks blocks by neglect, worst first.

**Two organisations within 7 days** is the duplication problem stated as a
query. This is the view that will interest SGSS most.

**Log a distribution** is the nine-field form. Leftovers are calculated from
prepared minus given out, never typed, so nobody can fudge the number that
matters.

---

## Why the schema looks like this

**Only one table is written to in the field.** `blocks` and `organisations` are
reference data you set up once. During a distribution, a volunteer touches
`distributions` and nothing else. Three of its nine fields are dropdowns.

**No recipient data, ever.** Records are at block level. No names, no NRIC, no
household identifiers, no income. This keeps the project clear of PDPA
obligations, avoids an ethics review, and makes partner organisations far more
willing to let you log their events. If someone suggests adding a recipient
table, that is the moment to push back.

**No unit counts.** The form records what food was given, where, when and by
whom. It does not record how much. Counting bundles at a live distribution needs
the organisation's cooperation and slows a volunteer down; what, where and when
are observable by anyone standing in the void deck. The `units_prepared` and
`units_given_out` columns still exist and are optional, so a later group can turn
counting back on without changing the schema.

What this costs you: surplus was the cheapest proxy for over-service. Duplication
now has to be shown through the overlap view (two organisations at one block
inside a week) rather than through leftovers.

**Duplicate protection.** A unique constraint on
(block, organisation, date, category) means two volunteers logging the same
event produces an error rather than double-counting.

**The 14 and 42 day thresholds are a guess.** They are written in one place, the
`block_coverage` view, and mirrored in `stateFor()` in the website. Change both
once you have watched the real cadence at Bedok. Do not present them as a
finding until you have.

---

## Honest limitations

- **The seed data is invented.** Block numbers, coordinates and every event are
  placeholders built to exercise the schema. Verify addresses against HDB's
  rental block listings and coordinates against OneMap before showing this to
  anyone as evidence.
- **Anyone signed in can log anything.** There is no approval workflow and no
  audit trail beyond `logged_by` and `created_at`. Fine for a pilot with people
  you know, not fine at scale.
- **Free-tier Supabase projects pause after a period of inactivity.** If the
  next group picks this up months later, the database may need waking from the
  dashboard. Consider exporting a CSV snapshot into the repo each month so the
  map still renders even if the database is asleep.
- **Nothing enforces that a logged event actually happened.** The data is only
  as good as the volunteers entering it, which is exactly why the form is nine
  fields and not twenty.
- **Coverage is computed in JavaScript in demo mode** and by the SQL view in
  live mode. The two are kept deliberately identical. If you change the
  thresholds, change both.

---

## Suggested next steps

Roughly in order of value for effort.

1. **Replace the seed with verified Bedok addresses.** Highest value, lowest
   difficulty, and it makes everything else honest.
2. **Log real sessions.** Bring paper the first time. Only build the phone
   workflow once you know the nine fields are the right nine.
3. **Add a printable weekly summary** for SGSS. A one-page PDF listing blocks
   not served in 30 days is more likely to change behaviour than a website
   nobody opens.
4. **Let organisations declare planned distributions,** not just past ones. The
   moment you can warn someone that another group is already visiting that block
   on Saturday, this stops being a record and starts being coordination. This is
   the real prize and is a sensible thing to leave for the next group.
5. **The physical button.** Your contact mentioned a device an organiser could
   press. An ESP32 posting to the same API is a weekend build and would cut
   logging friction to near zero. Treat it as phase two.

---

## Connecting a Google Form

The built-in form on the website works, but a Google Form is often easier in the
field: volunteers already have the link, it works offline-ish on a phone, and
you can share it with partner organisations without giving them anything else.

Responses reach the map within seconds. There is no spreadsheet to sync.

### 1. Add the bridge to the database

Run `forms_bridge.sql` in the Supabase SQL Editor (use `forms_bridge_plain.sql`
if you hit a paste error). It adds one function, `log_distribution`, which takes
plain text like "Blk 16 Bedok South Road" and resolves it to the right record.

The form can call this function and nothing else. It cannot read, edit or delete
your data, which makes it safer than opening the tables directly.

### 2. Get your dropdown options

In the SQL Editor run:

```sql
select * from form_dropdown_options order by question, option_text;
```

This prints the exact text your form dropdowns must use. Copy each group into
the matching question.

### 3. Build the form

Ten questions. The titles must match exactly, including capitalisation.

| Question title | Type | Required |
|---|---|---|
| Block | Dropdown (paste from the view) | Yes |
| Organisation | Dropdown (paste from the view) | Yes |
| Date | Date | Yes |
| Food category | Dropdown (paste from the view) | Yes |
| Units prepared | Short answer, number | No |
| Units given out | Short answer, number | No |
| Start time | Time | No |
| End time | Time | No |
| Notes | Paragraph | No |
| Your name | Short answer | No |

If you want different titles, change the left-hand side of `QUESTION_TITLES` in
the script instead of renaming the database fields.

### 4. Wire it up

In the form, click the three-dot menu and choose Apps Script. Delete the starter
code, paste in `google_form_bridge.gs`, and fill in your Project URL and anon
key at the top.

Run `testConnection()` from the toolbar first. It writes nothing and tells you
whether your URL and key are right. Then run `setUpTrigger()` once. Google will
warn that the script is unverified; that is expected for a script you wrote
yourself.

Submit a test response and check the Executions tab. A green tick means the
record is in the database. Refresh the website and the marker will have moved.

### What happens on a resubmission

If someone submits the same block, organisation, date and food category twice,
the second submission **updates** the first rather than creating a duplicate.
Volunteers correcting a typo is far more common than two genuinely separate
distributions of the same food to the same block on the same day.

### Microsoft Forms

The same design works, but the free path is worse. Microsoft Forms has no
built-in scripting, so you need Power Automate to forward responses, and its
HTTP action is a premium connector that most student accounts do not include.
Check what your NTU account covers before committing.

Two workarounds if Power Automate is unavailable: export the responses to Excel
and paste them into the Supabase Table Editor periodically, or just use Google
Forms. Unless there is a reason you need Microsoft, Google Forms is the shorter
path.

---

## Food categories

Nine categories, defined in three places that must agree:

- `schema.sql` — the CHECK constraint on `distributions.food_category`
- `index.html` — the `FOOD_CATEGORIES` list
- `forms_bridge.sql` — the `form_dropdown_options` view

To change them, edit all three, then run this in Supabase to update the
constraint on an existing database:

```sql
alter table distributions drop constraint distributions_food_category_check;
alter table distributions add constraint distributions_food_category_check
  check (food_category in ('Canned food', 'Your new category', ...));
```

Keep the list short enough to scan on a phone. Every category you add is another
thing a tired volunteer has to read at the end of a distribution.

---

## Regenerating the seed

```bash
python3 generate_seed.py     # rewrites seed_bedok.sql and demo_data.js together
```

Edit the `BLOCKS`, `ORGS` and `SCHEDULE` definitions at the top of that file.
Editing either output by hand will make them disagree.
