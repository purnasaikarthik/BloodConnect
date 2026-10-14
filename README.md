# BloodConnect

A blood banking website (HTML, CSS, JavaScript) with a Supabase database and free email alerts through Gmail.

## Features
- Home page with live donor count, blood availability and 24-hour emergency posts
- Give Blood form: adds a donor and raises that blood group's stock by one
- Want Blood form: emails every approved hospital; requests due in under 24 hours appear as emergencies
- Hospital sign up and login (a new hospital cannot log in until the admin approves it)
- Camps: approved hospitals post camps, everyone else can only view them
- Admin panel: approve or reject hospitals, edit blood availability, delete donors, requests, camps and hospitals, download a PDF report

## Folder
- `index.html`: the whole website (your Supabase URL and anon key are at the top of its script)
- `supabase/schema.sql`: creates the database (run once)
- `supabase/email-trigger.sql`: connects the database to the email script (run last)
- `email/Code.gs`: the Google Apps Script that sends the emails

## Setup, in this order

### Part 1: Supabase
1. **Authentication > Sign In / Providers > Email**: turn **off** "Confirm email" and save.
2. **SQL Editor > New query**: paste all of `supabase/schema.sql` and run it once. It must say Success.
3. **Authentication > Users > Add user > Create new user**: enter the admin email and a password, tick **Auto Confirm User**.
4. In the SQL Editor run (use the admin email from step 3):
   ```sql
   update public.profiles set role = 'admin', status = 'approved', hospital_name = 'Admin'
   where email = 'YOUR_ADMIN_EMAIL';
   ```
   It must say "1 row affected".
5. **Project Settings > API Keys > Legacy anon, service_role API keys**: click **Reveal** on `service_role` and copy it. You need it in step 7. Never put it in the website or on GitHub.

### Part 2: Google Apps Script (sends the emails)
6. Sign in to Google as the project mail (godofnewworld01@gmail.com). Open [script.google.com](https://script.google.com), click **New project**, delete the sample code, paste `email/Code.gs`, press Ctrl+S.
7. **Project Settings (gear) > Script Properties**: add three properties and save.
   - `SUPABASE_URL` = your project URL
   - `SERVICE_KEY` = the `service_role` key from step 5
   - `SECRET` = any made-up text with letters and numbers only (not a Supabase key). Keep it for step 10.
8. In the code view choose `testEmail` and click **Run**. Review permissions, Advanced, Go to project (unsafe), tick every box, Allow. The log shows "no approved hospitals" for now. That is fine.
9. **Deploy > New deployment > Web app**: Execute as **Me**, Who has access **Anyone**, Deploy, copy the **Web app URL** (ends with `/exec`).

### Part 3: Connect the database to the script
10. Open `supabase/email-trigger.sql`, replace `YOUR_WEB_APP_URL` and `YOUR_SECRET` (the same text as step 7), paste it in the SQL Editor and run it.

### Part 4: Publish the website
11. On Netlify open your site > **Deploys** and drag the whole `blood-connect` folder onto the upload area.

### Part 5: Test everything
12. Log in with the admin email: the Admin panel opens.
13. Sign up a test hospital with a different email that you can read. Log in as admin and approve it.
14. Submit a Want Blood request. The test hospital receives the email within a minute.
15. In the Admin panel delete the test hospital, then submit another request. No email arrives for it.
16. Delete your test data in the Admin panel.

## Troubleshooting
- **Sign up says "Database error saving new user"**: `schema.sql` was not run completely. Use a fresh project and run it once.
- **Script says forbidden**: the SECRET in `email-trigger.sql` differs from the `SECRET` script property.
- **Check what Supabase got back**: `select id, status_code, content, created from net._http_response order by created desc limit 5;`
- After editing `Code.gs`: **Deploy > Manage deployments > edit > New version**.

## Security notes
- Only the public anon key belongs in `index.html`. Never commit the `service_role` key, the `SECRET`, or `email-trigger.sql` with real values filled in.
- Free Gmail can send to about 100 recipients per day, one per approved hospital per request.
- Emergency posts show the patient's name, address and mobile publicly so donors can respond.

## License
MIT
