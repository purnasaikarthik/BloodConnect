/**
 * BloodConnect: free email alerts using your own Gmail through Google Apps Script.
 * Supabase calls doPost() whenever a row is added to the "requests" table.
 * Setup steps are in README.md ("Free email alerts").
 */

function doPost(e) {
  const props = PropertiesService.getScriptProperties();
  if (!e.parameter || e.parameter.key !== props.getProperty('SECRET')) return reply('forbidden');
  try {
    const payload = JSON.parse(e.postData.contents);
    if (payload.type !== 'INSERT' || payload.table !== 'requests') return reply('ignored');
    return reply(notify(payload.record));
  } catch (err) { return reply('error: ' + err.message); }
}

function notify(r) {
  const props = PropertiesService.getScriptProperties();
  const key = props.getProperty('SERVICE_KEY');
  // Emails of hospitals and blood banks that the admin has approved
  // Works with both key styles: new "sb_secret_..." keys (apikey header only) and legacy service_role keys
  const headers = { apikey: key };
  if (key.indexOf('sb_secret_') !== 0) headers.Authorization = 'Bearer ' + key;
  const res = UrlFetchApp.fetch(
    props.getProperty('SUPABASE_URL') + '/rest/v1/profiles?select=email&role=eq.hospital&status=eq.approved',
    { headers: headers, muteHttpExceptions: true });
  const emails = JSON.parse(res.getContentText()).map(function (x) { return x.email; }).filter(Boolean);
  if (!emails.length) return 'no approved hospitals';

  const needed = new Date(r.needed_by);
  const hours = Math.max(1, Math.round((needed - new Date()) / 36e5));
  const left = hours < 48 ? hours + ' hours' : Math.round(hours / 24) + ' days';
  const by = Utilities.formatDate(needed, 'Asia/Kolkata', 'dd MMM yyyy, hh:mm a');
  // Plain, specific subject (no ALL CAPS or "!!!") keeps the mail out of spam
  const subject = (r.is_emergency ? 'Urgent: ' : '') + r.blood_group + ' blood needed within ' + left + ' for ' + r.name;

  const rows = [
    ['Patient', r.name], ['Age', r.age], ['Gender', r.gender], ['Blood group', r.blood_group],
    ['Needed by', by], ['Mobile', r.mobile], ['Address', r.address]
  ];
  const text = 'A patient needs blood through BloodConnect.\n\n' +
    rows.map(function (x) { return x[0] + ': ' + x[1]; }).join('\n') +
    '\n\nIf you can help, please contact the patient directly.';
  const html = '<p>A patient needs blood through BloodConnect.</p><table cellpadding="6">' +
    rows.map(function (x) { return '<tr><td><b>' + x[0] + '</b></td><td>' + esc(x[1]) + '</td></tr>'; }).join('') +
    '</table><p>If you can help, please contact the patient directly.</p>';

  // Each approved hospital gets its own email, so nobody else (not even the sender) is a recipient
  const seen = {}; let sent = 0;
  emails.forEach(function (addr) {
    const to = String(addr).trim().toLowerCase();
    if (!to || seen[to]) return;
    seen[to] = true;
    MailApp.sendEmail({ to: to, subject: subject, body: text, htmlBody: html, name: 'BloodConnect' });
    sent++;
  });
  return 'sent to ' + sent;
}

// Run this once from the editor: it asks for permissions and sends a test alert.
function testEmail() {
  Logger.log(notify({
    name: 'Test Patient', age: 30, gender: 'Male', blood_group: 'O+', mobile: '9999999999',
    address: 'Test address', needed_by: new Date(Date.now() + 5 * 36e5).toISOString(), is_emergency: true
  }));
}

function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }
function reply(t) { return ContentService.createTextOutput(t); }
