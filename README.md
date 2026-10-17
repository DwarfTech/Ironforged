# Ironforged

The guild addon for Ironforged, an all-dwarf guild in World of Warcraft: Forever. It handles the roster, clans, promotion trials, events, Looking for Dwarf groups, a profession directory, the Book of Grudges, the Blood Tally and backstories, and it watches for non-dwarves in the hold. Everything recorded in it is shared automatically with every guildmate who has Ironforged installed.

Open it with the gold hammer button on the minimap, from the addon list beside the minimap, or with `/hold` (or `/ironforged`).

## Speak Dwarvish

The big **Dwarvish: ON/OFF** button at the top of the window sets your chat language to Dwarvish, the same as picking it from the game's chat language menu. Fellow dwarves understand you, and everyone else sees gibberish. The choice is remembered for each character and re-applied every time you open chat. You can also right-click the minimap button or type `/hold dwarvish`. Dwarvish is on by default for new installs. Only characters who know Dwarvish can turn it on.

## Cheers

Officers press **Call for Cheers!** at the top of the window, or type `/hold cheers`. The call goes out in guild chat, and everyone with the addon also gets a banner and a Cheers popup with a button to drink an ale from their bags. Ales and stouts are picked first, then other drinks. Each dwarf who drinks announces it in guild chat ("Kurdran chugs a Thunder Ale! Cheers to Frugo! That's 3 mugs raised to the call."), and the popup lists who has drunk so far. One drink per dwarf per call. Calls last 3 minutes, and an officer can call once a minute. Cheers and Cross Gambling are the only parts of the addon that post to chat. Members can turn the popup off in Settings.

## Cross Gambling

The **Gambling** button at the top of the window, beside Call for Cheers!, opens Cross Gambling for the guild, party or raid.
1. A host sets the gold amount, picks guild, party or raid chat, and presses **Open game**. The game is posted in that chat, and guildmates with the addon get a popup.
2. Players type **1** in that chat to join, or **-1** to leave (addon users can press Join). The host can post a **Last call**.
3. The host presses **Start rolling**. Everyone rolls 1 to the amount (`/roll 500`, or the Roll button).
4. The highest roll wins, and the lowest roll pays the winner the difference between their rolls. Ties for highest or lowest roll again among the tied players.
5. The result is posted in the game's chat. Gold changes hands by trade; the addon only keeps score.

The host can click a player's name in the players list to remove them from the game at any point. If a game drops below two players after rolling starts, it is cancelled.

The **Hall of Fortune** beside the table shows every dwarf's net gold and games played across all recorded games. In a guild game, players far from the host report their own roll through the addon, so they need the addon; in a party or raid game, anyone in the group can play. Officers can delete a recorded game. Members can turn the popup off in Settings.

## Titles

Officers press **Award title** on any member's record to give them a title. They can pick a suggested one (Shieldbreaker, Stoneborn, Keg Champion, Runekeeper, Stonewarden, Oathkeeper, Hammer of the Hold, Deepdelver, Brewmaster, Forgemaster, Ironbrow, Mountain's Shield) or type their own, with an optional reason. The member gets a popup. **Strip title** takes one away. A member can hold any number of titles.

Some titles are earned automatically and move to whoever holds the record. Ties share the title.
- **Elfbane:** most elves slain
- **The Hordebreaker:** most Horde slain
- **The Grudgebearer:** most grudges avenged
- **The Goldbringer:** most gold won at Cross Gambling

Titles show on the member's record, in the roster's Title column, and on their tooltip.

## Invite from whispers

Like Leatrix Plus: when a guildmate whispers you **inv**, you invite them to your group automatically. It works when you're solo, or when you lead the group (or have assist in a raid) and there's room. In Settings you can change the keyword (several work, separated by commas, such as `inv, 123`), allow anyone to be invited this way rather than only guildmates, or turn it off.

## Tabs

The side list is split into three sections: **Guild Management** (Roster, Clans, Promotions, Events), **In Game** (Looking for Dwarf, Professions, Challenges) and **Roleplay** (Book of Grudges, Blood Tally, Backstory), with Settings at the bottom.

Every list can be sorted: click a column title to sort by it, and click again to reverse.

**Roster.** Every guildmate with rank, level, clan, title, race check and when they were last seen. Tick "Rule problems" to list only non-dwarves, and members flagged "(shamed)" for inviting a non-dwarf. "Scan races" looks up members who don't have the addon. Click a name for the full record: clan, titles, alts, who invited them, attendance, trials and backstory. Officers can edit the record and press **Manage**, which gives the `/gpromote`, `/gdemote` or `/gremove` command to copy and paste into chat.

**Clans.** Veterans and above can found a clan, and the founder is always its Clan Leader. Members join in two ways: the Clan Leader invites them, or they press **Ask to join** on the clan's page. Clan Leaders and officers press **Applications** to see who has asked, then click an applicant to accept or deny them. Only Longbeards and the guild master can delete a clan.

**Promotions.** Press **Give a trial**, pick the member and the rank it earns, and write up to 10 tasks. Leave the tasks blank to use suggested ones for that rank. Members can press **Request promotion**, but a trial can be given without a request. Every character's trial is visible to the whole guild. The member on the trial can tick their own tasks as they finish them and press Save progress. The officer who can give that trial sees which tasks the member marked, can untick any they don't accept, and is the only one who can complete the trial and promote. When every task is done, **Trial complete** gives the `/gpromote Name` command to copy and paste into chat; run it once per rank until they reach the trial's rank. Once all tasks are done and the member holds the trial's rank, the trial clears itself from the list for everyone.

**Events.** Officers schedule raids, gatherings and ceremonies. Everyone marks Going, Maybe or Can't go. Officers press **Take attendance** to record who showed up.

**Looking for Dwarf.** A group board for the guild. Type what the group is for ("Gnomeregan"), how many dwarves you need, and an optional note, then press **Post**. Every guildmate with the addon who is online gets a popup and signs up as Tank, Healer or Damage with one click. Nothing is posted in chat. The leader gets a popup for each sign-up with an **Invite** button, and the post's page has **Invite all**. You can sign up or drop out from the tab too. Each leader has one post at a time; posts close after two hours, when the leader goes offline, or when the leader presses **Close my post**. Officers can take down any post. Members can turn the popups off in Settings.

**Professions.** The hold's profession directory. Each member's professions and skill levels are recorded automatically when they log in. Their recipes are recorded the first time they open each profession window, and again whenever they learn more. Search a recipe ("bronze axe") to see every dwarf who can make it, online crafters first. Click a recipe to ask that dwarf to craft it: they get a private popup with your note, and nothing goes to chat. With the search empty, the tab shows one row per profession, with how many dwarves have it, how many are online and who is most skilled. Click a profession to see its dwarves, best first, then click a dwarf to see everything they can make. **Back** steps out a level, and **Online only** hides anyone offline.

**Challenges.** Press **Take on a challenge** and pick a ready-made one or write your own. Your own challenges run on your honor: you mark them completed or give up. The ready-made ones must be started at level 1, and the addon enforces them:
- **Slayer:** no chest or shoulder armor, and you stay flagged for PvP all the way to max level. Chest or shoulder armor you put on goes straight back into your bags, and your PvP flag is switched back on if it drops.
- **Stone-Skin:** no armor at all. Weapons, rings, necklace, trinkets, shirt and tabard only. Armor goes straight back into your bags.
- **Self-Made:** no auction house, trading or mail. They close as soon as they open.
- **One Life:** die once and the challenge is over.
- **Dwarf Found:** trade and group only with dwarves. Trades with anyone else are cancelled, invites from guildmates known not to be dwarves are turned down, and if a non-dwarf joins your group you get 15 seconds to remove them before you leave the group.

If forbidden armor can't come off (your bags are full), you get a warning and one minute to remove it before the challenge fails. Ready-made challenges complete themselves at max level. The tab shows every dwarf's challenges, with the level they started at, their level now and how it went, and guildmates with the addon are told when a challenge starts, fails or is completed. Officers can remove any challenge from the list.

**Book of Grudges.** Anyone can write a grudge against someone outside the guild: who, their side (Horde or Alliance), where, and what they did. "Grudge my target" fills in your target's first and last name, their side, and the zone you're in. Guildmates can't be grudged. Everyone can read the book, with unavenged grudges listed first.
- A **Horde** grudge is avenged automatically when a guildmate with the addon gets an honorable kill on that foe, or sees them dead. The whole guild is told who avenged it.
- An **Alliance** grudge is avenged by an officer with **Mark avenged**, choosing who gets the credit. Officers can also mark a Horde grudge by hand, or reopen one.
- The first time a grudged foe shows up on your nameplates, target or mouseover, you get a raid-warning alert and a sound, and the guild is told who spotted them and where. Each grudge alerts only once. A popup also offers to **/doom** them: press the button and you threaten the foe with the wrath of doom (the game's /doom emote, aimed at them). Their tooltip always shows a red "GRUDGE" line with what they did. You can turn alerts or the /doom popup off in Settings.
- Avenged grudges are stamped **AVENGED** in the book, with who avenged them and when.
- Only officers can strike a grudge out.

**Blood Tally.** A leaderboard of every dwarf's Horde slain (their lifetime honorable kills), elves slain, and grudges avenged, ranked by Horde slain. Click a column title to sort by another. The tally also shows on each member's roster record. The line above the board names the current **Elfbane**, **Hordebreaker** and **Grudgebearer**, and their rows are tagged and highlighted. Clicking a dwarf here shows their record without the management buttons.

**Backstory.** Your character's backstory and your standing in the hold.

**Settings.** Officers set the hold name. Each member chooses their notices, popups, tooltips and whether to show the minimap button.

## Rank powers

These are fixed and read from your in-game guild ranks:
- Officers are the Longbeards and the guild master. They manage events, member records, the hold name, can remove members, and get the non-dwarf popup.
- Nobles and above give promotion trials for ranks below Noble.
- Longbeards and the guild master give any trial, including Noble, Lord and Overlord.
- Veteran and above can found a clan.
- Only officers can delete clans and strike grudges.

The game itself still decides who may promote and remove members, based on each rank's permissions in Guild Control.

## Keeping the hold dwarven

- **Race.** Each member's addon reports their race. "Scan races" and grouping, targeting or mousing over someone fill in the rest.
- **Invites.** Every guild invite is logged by the inviter's addon, including the invitee's race when it's known.
  - If someone invites a non-dwarf, everyone with the addon sees who invited whom in chat.
  - The inviter is marked "(shamed)" on the roster, and the non-dwarf's row shows "(invited by ...)".
  - Officers get a popup.
- **New members.** When a non-dwarf joins or is found in the guild, everyone gets the same alert and popup, including who invited them if it was logged.
- **Gear.** The dwarf-crafted, enchanted gear rule is kept on the honor system. The addon doesn't check it.

## How kills are counted

Forever locks the combat log, so the addon counts kills from the game's "X dies, honorable kill" message. Elves are counted when the addon knows the victim's race, which it learns from their nameplate, your target or a mouseover, usually before the fight. Kills that don't give honor, like duels or the same player killed too often, aren't counted.

## Installing (for each guildmate)

1. If you had the earlier test version, delete its `Stonehold` folder from AddOns.
2. Unzip `Ironforged.zip` and move the `Ironforged` folder into your WoW: Forever `Interface\AddOns` folder. Check the result: you should have `...\Interface\AddOns\Ironforged\Ironforged.toc`.
3. Restart the game and make sure Ironforged is ticked in the AddOns list at character select.

If the game shows it as "out of date", type `/dump select(4, GetBuildInfo())` and change the number on the first line of `Ironforged.toc` to match.

Everyone needs the same version for records to sync. An older copy tells its owner to update.

## Commands

- `/hold` (or `/if`, `/ironforged`) opens the hold.
- `/hold dwarvish` turns speaking Dwarvish on or off.
- `/hold cheers` (officers) calls the hold to raise a mug.
- `/hold sync` asks guildmates for the latest records.
- `/hold status` shows who the addon thinks you are and your rank.

## Notes

- Blizzard blocks any promotion or removal an addon starts, including commands an addon types into your chat box. The addon gives you the command to copy; you paste it and press Enter, or use the guild window yourself.
- Names follow Forever's first-and-last-name system. Grudges, alerts and kill tracking match on the full name. A grudge written with only a first name matches anyone with that first name, so add the surname when you know it.
- A non-dwarf's race can only be known once someone with the addon has seen them, or they've installed it.
- Trial accounts can't send addon messages in Forever, so their edits don't reach others.

## For developers

The addon's code lives in a git repository.
- `tests/` holds a mock WoW client and the test suite. Run it with Lua 5.1: `cd tests && lua5.1 tests.lua ..`
- On GitHub, every push and pull request runs the tests automatically (`.github/workflows/tests.yml`).
- When the version in `Ironforged.toc` changes on `main`, GitHub tags it, builds `Ironforged.zip` and publishes it as a release (`.github/workflows/release.yml`). It can also be run by hand from the Actions tab. Guildmates can download the latest version from the repository's Releases page.
