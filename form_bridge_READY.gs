/**
 * Google Form -> Food Aid Coverage Tracker
 *
 * Forwards each form response to the database the moment it is submitted,
 * so the map updates within seconds. No spreadsheet syncing, no manual
 * import step.
 *
 * SETUP
 *  1. Build the form (see README section "Connecting a Google Form").
 *  2. In the form, click the three dots -> Apps Script.
 *  3. Delete whatever is there, paste this file in.
 *  4. Fill in SUPABASE_URL and SUPABASE_ANON_KEY below.
 *  5. QUESTION_TITLES below already matches the live form
 *     "Food Distribution Consolidation Form". If you ever reword a
 *     question, update the matching left-hand side here too.
 *  6. Run setUpTrigger() once from the toolbar. Approve the permissions
 *     prompt (it will warn the script is unverified; that is normal for
 *     your own script).
 *  7. Submit a test response and check the Executions tab.
 */

// ---------------------------------------------------------------
// PUT YOUR TWO VALUES BETWEEN THE QUOTES ON THESE TWO LINES.
// Nothing goes after the semicolon.
// ---------------------------------------------------------------
const SUPABASE_URL      = '';
const SUPABASE_ANON_KEY = '';

/**
 * Left side  = the exact title of your Google Form question.
 * Right side = the field the database expects. Do not change the right side.
 */
const QUESTION_TITLES = {
  'Where did the distribution happen?':      'location',
  'Postal Code':                             'postal_code',
  'Which organisation ran the distribution?': 'organisation',
  'Date':                                    'date',
  'What food was given out?':                'food_category',
  'Anything else you noticed?':              'notes'
};

/**
 * Corrects form wording that does not exactly match the nine categories the
 * database accepts. Left side = what the form sends, right side = what the
 * database expects. Add a line here whenever you spot a mismatch, instead of
 * editing the live form mid-project.
 */
const FOOD_ALIASES = {
  'Dry food (Rice, noodles, biscuits)': 'Dry food (rice, noodles, biscuits)'
};


/** Runs automatically on every form submission. */
function onFormSubmit(e) {
  const answers = {};
  e.response.getItemResponses().forEach(function (item) {
    const field = QUESTION_TITLES[item.getItem().getTitle().trim()];
    if (!field) return;                       // question we don't care about
    const raw = item.getResponse();
    if (field === 'food_category') {
      answers[field] = (Array.isArray(raw) ? raw : [raw])
        .map(function (v) { return String(v).trim(); })
        .filter(function (v) { return v !== ''; })
        .map(function (v) { return FOOD_ALIASES[v] || v; });
      return;
    }
    const value = String(raw).trim();
    if (value !== '') answers[field] = value;
  });

  const foods = answers.food_category || [];
  if (!answers.location || !answers.organisation || !foods.length) {
    throw new Error('Missing a required answer. Got: ' + JSON.stringify(answers));
  }

  const results = [];

  foods.forEach(function (food) {
    const payload = {
      p_location:       answers.location,
      p_postal_code:    answers.postal_code || null,
      p_organisation:   answers.organisation,
      p_distributed_on: answers.date ? normaliseDate(answers.date) : todayInSingapore(),
      p_food_category:  food,
      p_notes:          answers.notes || null,
      p_logged_by:      answers.logged_by || null
    };

    const r = UrlFetchApp.fetch(SUPABASE_URL + '/rest/v1/rpc/log_distribution_freetext', {
      method: 'post',
      contentType: 'application/json',
      headers: {
        apikey: SUPABASE_ANON_KEY,
        Authorization: 'Bearer ' + SUPABASE_ANON_KEY
      },
      payload: JSON.stringify(payload),
      muteHttpExceptions: true
    });
    results.push({ food: food, code: r.getResponseCode(), body: r.getContentText() });
  });

  const failed  = results.filter(function (x) { return x.code < 200 || x.code >= 300; });
  const pending = results.filter(function (x) { return x.body.indexOf('pending') !== -1; });

  if (failed.length) {
    throw new Error('Database rejected ' + failed.length + ' of ' + results.length
      + ': ' + JSON.stringify(failed));
  }
  console.log('Submitted ' + results.length + ' record(s). '
    + (pending.length ? pending.length + ' waiting in pending_review.' : 'All matched.'));
}


/** Google Forms returns dates as a full timestamp; the database wants YYYY-MM-DD. */
function normaliseDate(value) {
  const d = new Date(value);
  if (isNaN(d.getTime())) return value;
  return Utilities.formatDate(d, 'Asia/Singapore', 'yyyy-MM-dd');
}

function todayInSingapore() {
  return Utilities.formatDate(new Date(), 'Asia/Singapore', 'yyyy-MM-dd');
}


/** Run this ONCE from the toolbar to start listening for submissions. */
function setUpTrigger() {
  const form = FormApp.getActiveForm();

  // Remove any duplicates from earlier attempts.
  ScriptApp.getProjectTriggers().forEach(function (t) {
    if (t.getHandlerFunction() === 'onFormSubmit') ScriptApp.deleteTrigger(t);
  });

  ScriptApp.newTrigger('onFormSubmit')
    .forForm(form)
    .onFormSubmit()
    .create();

  console.log('Trigger created. Submit a test response to check it works.');
}


/**
 * Optional sanity check. Run this from the toolbar to confirm your URL and
 * key are correct WITHOUT submitting a form. It writes nothing.
 */
function testConnection() {
  const res = UrlFetchApp.fetch(SUPABASE_URL + '/rest/v1/blocks?select=block_no,street&limit=3', {
    headers: {
      apikey: SUPABASE_ANON_KEY,
      Authorization: 'Bearer ' + SUPABASE_ANON_KEY
    },
    muteHttpExceptions: true
  });
  console.log('HTTP ' + res.getResponseCode());
  console.log(res.getContentText());
  console.log(res.getResponseCode() === 200
    ? 'Connection works. You can run setUpTrigger() now.'
    : 'Check SUPABASE_URL (no trailing slash) and SUPABASE_ANON_KEY.');
}
