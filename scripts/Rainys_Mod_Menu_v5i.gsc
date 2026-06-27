/*
    Rainy's IW4x .GSC Trickshot Mod Menu
    Released under the GNU General Public License v3.0.

    Credits:
    - Rainy City: IW4x .GSC trickshot menu development, edits, testing,
      organization, and release.
    - SyndiShanX / Synergy MW2 GSC Menu: portions of submenu code, structure,
      dvars, functions, and implementation patterns were adapted from or
      directly based on Synergy.
    - ineedbots / Bot Warfare: bot system, waypoint/scriptdata foundation,
      and related bot support.
    - IW4x community: client, documentation, testing knowledge, and modding
      resources.

    This project is intended for private matches, bot practice, and community
    modding. Do not use it for public cheating, selling, or claiming credited
    work as your own.
*/

#include maps\mp\_utility;
#include maps\mp\bots\_bot_utility;
#include maps\mp\gametypes\_hud_util;
main()
{
    init();
}
init()
{
    if (isDefined(level.trickshotToolsInitialized) && level.trickshotToolsInitialized)
        return;
    level.trickshotToolsInitialized = true;
    level.rainyLevelShuttingDown = false;
    // trickshotToolsStarted is a per-PLAYER field, not a per-LEVEL one. If a player's
    // entity survives across a genuine map change (loading a different/custom map),
    // the same way self.ufoEnabled was already found to, this flag being left over as
    // "true" would make trickshotPlayerBootstrap's loop skip calling trickshotTools()
    // again entirely on this new level - silently skipping EVERY reset that function
    // does (UFO, FOV, speed, canswap bind, killcam preference, all of it), not just
    // UFO. init() itself is already correctly guarded to run exactly once per fresh
    // level (the check just above), so this is the right, safe place to force any
    // already-connected players to bootstrap again on this new level too.
    if (isDefined(level.players))
    {
        for (i = 0; i < level.players.size; i++)
        {
            if (isDefined(level.players[i]))
                level.players[i].trickshotToolsStarted = undefined;
        }
    }
    // Keep the stock/global killcam gate available. Host-only Killcams OFF is handled
    // with the host victim's cancelKillcam flag below; if level.killcam is left false,
    // toggling the host back ON can never bring normal killcams back.
    rainyEnsureGlobalKillcamAvailable();
    rainyEnsureBotTeamDvars();
    precacheShader("cardicon_prestige10_02");
    setDvar("ts_endgame", "0");
    level.trickshotDamageOnly = false;
    level.rainyFriendlyFire = false;
    rainyApplyFriendlyFireState(false);
    // Bot movement defaults to ON at match start. This dvar was previously only ever
    // set by the explicit Freeze/Unfreeze Bots and All Players freeze/unfreeze actions
    // - nothing established a baseline "bots can move" default, so freshly-added bots
    // inherited whatever the engine/Bot Warfare default for this dvar happened to be
    // (apparently movement-disabled) until the host happened to toggle freeze once,
    // which is what actually flips it to "1" for the first time. level.botsFrozen is
    // also set explicitly here for clarity, matching this dvar's default state.
    level.botsFrozen = false;
    setDvar("bots_play_move", "1");
    // Canswap Bind defaults ON lobby-wide (see trickshotTools), so the All
    // Players page 2 toggle display needs to start true too, or it would
    // show [OFF] while every player's individual bind is actually active.
    level.rainyAllCanswap = true;
    level.rainyNoPlayerCollision = false;
    precacheItem("usp_akimbo_mp");
    precacheItem("coltanaconda_akimbo_mp");
    precacheItem("beretta_akimbo_mp");
    precacheItem("deserteagle_akimbo_mp");
    precacheItem("deserteaglegold_akimbo_mp");
    precacheItem("pp2000_akimbo_mp");
    precacheItem("glock_akimbo_mp");
    precacheItem("beretta393_akimbo_mp");
    precacheItem("tmp_akimbo_mp");
    precacheItem("ranger_akimbo_mp");
    level thread trickshotGlobalEndGameMonitor();
    level thread trickshotPlayerBootstrap();
    level thread installRainyDamageHook();
    level thread rainyNightVisionDisableManager();
    level thread rainyCarePackageKeepAliveLoop();
}
trickshotGlobalEndGameMonitor()
{
    level endon("game_ended");

    for (;;)
    {
        if (getDvar("ts_endgame") == "1")
        {
            setDvar("ts_endgame", "0");
            level.rainyLevelShuttingDown = true;
            level notify("rainy_shutdown");
            // No "self" here - this loop runs at level scope, not on a player entity.
            // rainyShowRaisedMessage needs a player to attach its HUD elements to, so
            // find the host the same way other level-scope loops in this file do
            // (iterate level.players and check isHost()).
            for (hostSearchIdx = 0; hostSearchIdx < level.players.size; hostSearchIdx++)
            {
                if (isDefined(level.players[hostSearchIdx]) && level.players[hostSearchIdx] isHost())
                {
                    level.players[hostSearchIdx] thread rainyShowRaisedMessage("^7F3 Instant End Game");
                    break;
                }
            }
            rainyResetTransientSettingsAllPlayers();
            wait 0.3;
            exitLevel(false);
        }
        wait 0.05;
    }
}
trickshotPlayerBootstrap()
{
    level endon("game_ended");
    level endon("rainy_shutdown");

    for (;;)
    {
        if (isDefined(level.rainyLevelShuttingDown) && level.rainyLevelShuttingDown)
            return;

        if (isDefined(level.players))
        {
            for (i = 0; i < level.players.size; i++)
            {
                player = level.players[i];
                if (isDefined(player) && !isDefined(player.trickshotToolsStarted) && !player isBot())
                {
                    player.trickshotToolsStarted = true;
                    player thread trickshotTools();
                }
            }
        }
        wait 0.5;
    }
}
trickshotTools()
{
    self endon("disconnect");
    level endon("game_ended");
    level endon("rainy_shutdown");

    self.menuOpen = false;
    self.menuIndex = 0;
    self.menuPage = "main";
    self.hasSavedPos = false;
    // UFO state must start clean on every fresh bootstrap, not just when the host
    // explicitly uses Restart Game/Instant End Game from the menu (see
    // rainyResetTransientPlayerSettings for that path). self.ufoEnabled/self.ufoEntity
    // are plain player fields - if this exact player entity persisted across an earlier
    // match in the same server session (e.g. backing out to the private match lobby and
    // pressing Start Game again, rather than using the in-menu restart), nothing else
    // resets them, and ufoRespawnWatcher will dutifully relink to whatever stale entity
    // self.ufoEntity still points to the moment this fresh match's first spawn fires -
    // producing a spawn far outside the map's normal play area. rainyTearDownUfo is safe
    // to call here even on a genuinely fresh connection with nothing to actually tear
    // down (already confirmed safe/idempotent via its use in toggleUFO and the restart
    // path above).
    self notify("StopUFO");
    self rainyTearDownUfo();
    self.lastUseState = false;
    self.lastMeleeState = false;
    self.lastAdsState = false;
    self.adsHeldTicks = 0;
    self.attackHeldTicks = 0;
    self.ignoreAdsRelease = false;
    self.ignoreAttackRelease = false;
    self.trickshotDistanceOn = true;
    self.almostHitsOn = true;
    self.rainyInfiniteCarePackage = false;
    self.rainyForgeMode = false;
    self.rainyNoScopeShotId = 0;
    self.rainyLastDirectHitShotId = -1;
    self.rainyWasHost = false;
    if (self isHost())
        self.rainyWasHost = true;
    // Canswap Bind defaults ON for every connecting player (host and
    // non-host alike), matching the menu's [ON]/[OFF] toggles for Canswap
    // Bind, All Players page 2, and the per-player submenu page 2 - all of
    // which read/flip self.canswapBound or target.canswapBound, so setting
    // it true here and starting the monitor makes the default consistent
    // everywhere the bind is shown or toggled.
    self.canswapBound = true;
    self thread canswapBindMonitor();
    // TS Platform Bind defaults ON (matches its menu toggle's default), gating
    // whether spawnPlatformBindMonitor's loop actually does anything below -
    // the monitor itself always starts and listens, the toggle just decides
    // whether a press is acted on, same model as canswapBound above.
    self.rainyTsPlatformBindOn = true;
    // UFO Mode / TS Aimbot / Spawn Trickshot Platform quick-toggle binds are
    // host-only (the host is the only one with menu access to these features
    // in the first place), so each monitor self-gates at the top rather than
    // wrapping the thread call here, matching how every other per-player
    // monitor in this function is started uniformly regardless of host status.
    self thread ufoBindMonitor();
    self thread tsAimbotBindMonitor();
    self thread spawnPlatformBindMonitor();
    // Killcams default OFF for the menu holder only (currently the host). The global
    // level.killcam gate stays ON so other players keep normal killcams and so the host
    // can actually restore killcams later. Host suppression is done with this victim's
    // cancelKillcam flag only.
    rainyEnsureGlobalKillcamAvailable();
    if (self.rainyWasHost)
        self.rainyKillcamsEnabled = false;
    self rainyApplyKillcamPreference();
    self thread rainyKillcamPreferenceLoop();
    self thread noFallDamage();
    self thread allowPlayerMovementAtMatchStart();
    self thread persistentHudMenuControls();
    self thread rainyToggleEffectsRespawnWatcher();
    self thread saveLoadBindMonitor();
    self thread rainyCleanupOnGameEnd();
    self thread rainyCleanupOnDisconnect();
    self thread rainyHeldWeaponPoll();
    self thread rainyGroundGunDeathWatch();
    self thread rainyFovPersistLoop();
    self thread rainyCamoPersistLoop();
    self thread rainySniperShotWatcher();
    self thread forceUAVSpawnPersistLoop();
    if (!isDefined(level.forceUAVInitialized))
    {
        level.forceUAVInitialized = true;
        level.forceUAV = true;
        level thread forceUAVLoop();
    }
    self.forceUAV = level.forceUAV;
    if (!isDefined(level.wallbangInitialized))
    {
        level.wallbangInitialized = true;
        setDvar("bg_surfacePenetration", "9999");
        setDvar("bg_bulletExplDmgFactor", "9999");
        setDvar("bg_bulletRange", "99999");
        setDvar("bg_penetrationMinDmgMult", "1.0");
        setDvar("bg_fallbackExplosionDamage", "9999");
        setDvar("bg_bulletDmgMultPenetrationSmall", "9999");
        setDvar("bg_bulletDmgMultPenetrationMedium", "9999");
        setDvar("perk_bulletPenetrationMultiplier", "30");
        setDvar("perk_armorPiercing", "9999");
        setDvar("bullet_ricochetBaseChance", "0.95");
        setDvar("bullet_penetrationMinFxDist", "1024");
        setDvar("bulletrange", "50000");
    }
    self.wallbangOn = true;
    // Keep the active wallbang penetration profile alive. Some game/bot/mod code can
    // re-push baseline dvars after spawn/state changes; this makes Wallbang Everything
    // and Wallbang + Snap Aim use the same damage profile consistently.
    self thread rainyWallbangDvarKeepAliveLoop();
    if (!isDefined(level.deathBarriersRemoved))
        level thread removeDeathBarriers();
    // Server-side baseline. The real lobby-wide enforcement (per client, re-applied on
    // respawn) is handled by rainyNightVisionDisableManager, started in init().
    setDvar("nightVisionDisableEffects", "1");
    self thread allowClassChangeAlways();
    wait 1;
    self thread rainyShowWelcomeBanner();
    for (;;)
        wait 1;
}
/*
    Replaces the old iPrintLnBold "Trickshot Tools Loaded" message.
    iPrintLnBold can't be resized, recolored beyond the ^-code palette, or
    have its on-screen duration changed - it's a fixed engine announce
    string. To get a controllable welcome message, this builds a real HUD
    element instead (same createFontString approach already used by
    createMenuText/createMenuTextFont) and destroys it itself afterward.

    Configstring-safe glitch intro: this keeps the look close to the earlier
    random scramble, but it does not generate endless random strings. It only
    cycles through a small set of fixed glitch phases, so the same HUD text
    strings get reused instead of overflowing G_FindConfigstringIndex.

    Position: sits between the Ranger logo and the "Waiting for more players..."
    message instead of stretching across the very top of the screen.
*/
rainyWelcomeGlitchCharForIndex(i, phase)
{
    glitchChars = "@#$%&*+!?/|<>=0123456789";
    idx = ((i * 11) + (phase * 7) + 3) % glitchChars.size;
    return getSubStr(glitchChars, idx, idx + 1);
}

rainyWelcomeColorForIndex(i)
{
    if (i % 2 == 0)
        return "^6";
    return "^7";
}

rainyBuildWelcomeGlitchText(msg, settledChars, phase)
{
    out = "";
    for (i = 0; i < msg.size; i++)
    {
        ch = getSubStr(msg, i, i + 1);

        if (ch == " ")
        {
            out += " ";
        }
        else
        {
            colorCode = rainyWelcomeColorForIndex(i);
            if (i < settledChars)
                out += colorCode + ch;
            else
                out += colorCode + rainyWelcomeGlitchCharForIndex(i, phase);
        }
    }
    return out;
}

rainyShowWelcomeBanner()
{
    self endon("disconnect");
    self endon("rainy_welcome_banner_shutdown");
    level endon("game_ended");
    level endon("rainy_shutdown");
    msg = "Welcome to Rainy's Mod Menu";
    // Time the fully-resolved message sits static on screen before the flash
    // sequence starts (below) - shortened from 8.5 per request. Flash behavior
    // itself (flashCount/flashDelay) is untouched.
    holdTime = 5.5;
    introLoops = 2;
    phaseCount = 3;
    introDelay = 0.12;
    glitchDelay = 0.07;
    settleDelay = 0.085;
    flashCount = 3;
    flashDelay = 0.22;
    banner = self createFontString("smallfixed", 2.45);
    banner setPoint("CENTER", "CENTER", 0, -88);
    banner.alpha = 1;
    // Sort intentionally kept BELOW every mod menu HUD element (backdrop sort 100 is
    // the lowest of the bunch - see createMenuHud) so the welcome banner always renders
    // behind the entire mod menu, never on top of it, even while both are visible at once.
    banner.sort = 50;
    banner.archived = false;
    banner.hideWhenInMenu = false;
    banner.foreground = true;
    banner.color = (1, 1, 1);
    banner.glowColor = (0.6, 0, 0.6);
    banner.glowAlpha = 0.48;
    banner set_text("");
    // Stored on self (not just held in the local "banner" var) as a backstop so
    // external teardown (rainyTeardownWelcomeBannerHud) can still reach and
    // destroy this element even if this thread has already exited and is no
    // longer listening for the endon below. The primary mechanism, though, is
    // rainy_welcome_banner_shutdown: teardown notifies that signal BEFORE it
    // destroys the hud, which kills this thread at its next wait/yield point
    // before any further banner.alpha/set_text writes can run - closing the
    // race where teardown destroys the element out from under this loop while
    // it's still mid-animation (destroy from one thread, then a property write
    // from this one, on the same now-deleted hud elem).
    self.rainyWelcomeBannerHud = banner;

    // Full-line corrupted intro. It cycles through three fixed phases rather
    // than using random text, keeping the old look without spamming unique strings.
    for (loop = 0; loop < introLoops; loop++)
    {
        for (phase = 0; phase < phaseCount; phase++)
        {
            banner set_text(rainyBuildWelcomeGlitchText(msg, 0, phase));
            wait introDelay;
        }
    }

    // Resolve left-to-right. Each unresolved section still flickers through the
    // same three fixed phases so the animation feels random, but stays safe.
    for (i = 0; i < msg.size; i++)
    {
        for (phase = 0; phase < phaseCount; phase++)
        {
            banner set_text(rainyBuildWelcomeGlitchText(msg, i, phase));
            wait glitchDelay;
        }

        banner set_text(rainyBuildWelcomeGlitchText(msg, i + 1, 0));
        wait settleDelay;
    }

    banner set_text(rainyBuildWelcomeGlitchText(msg, msg.size, 0));
    wait holdTime;
    // Flash a few times right before it leaves instead of just cutting out.
    for (f = 0; f < flashCount; f++)
    {
        if (!isDefined(banner))
            break;
        banner.alpha = 0.15;
        wait flashDelay;
        if (!isDefined(banner))
            break;
        banner.alpha = 1;
        wait flashDelay;
    }
    if (isDefined(banner))
        banner destroy();
    self.rainyWelcomeBannerHud = undefined;
}
rainyTeardownWelcomeBannerHud()
{
    // External teardown path for rainyShowWelcomeBanner's HUD element. Notify
    // BEFORE destroy (same order as rainyTeardownMsgStackHud/rainyTeardownBroadcastHud):
    // this kills rainyShowWelcomeBanner's thread at its next wait/yield point via its
    // own endon, so it can't touch the hud after this destroys it. The destroy() call
    // below is then a backstop for the case where that thread already exited on its
    // own (banner finished naturally, or died via disconnect/game_ended/rainy_shutdown)
    // and is no longer listening for the notify at all.
    self notify("rainy_welcome_banner_shutdown");
    if (isDefined(self.rainyWelcomeBannerHud))
    {
        self.rainyWelcomeBannerHud destroy();
        self.rainyWelcomeBannerHud = undefined;
    }
}
/*
    iPrintLnBold is a fixed engine announce string - it always renders at the
    engine's built-in position and GSC cannot move it (see the comment on
    rainyShowWelcomeBanner above). That fixed position sits right on top of/behind
    the "Welcome to Rainy's Mod Menu" banner text, so any iPrintLnBold message
    visually collided with it.

    This mirrors the existing broadcast/shot-feed system (rainyAddBroadcastFeedEntry /
    rainyRenderBroadcastSlots / rainyBroadcastFadeLoop, used by hitmarkers, almost-hits,
    and Trickshot Distance) instead of inventing a different animation model. That
    system's own comment spells out the exact lesson this needed: HUD slots are created
    ONCE at fixed positions and never setPoint'd again - only which message/alpha
    occupies each slot changes on every render pass. Calling setPoint repeatedly (the
    old version of this code did, to "slide" entries) replays each HUD element's entry
    transition, which is what produced the "flies in from the left" glitch instead of a
    clean push-up.

    Same idea here, just with its own slot count/position (anchored above the welcome
    banner) and its own hold/fade timing. As of this version, EVERY menu/keybind
    feedback message in the mod (toggle confirmations, give/remove confirmations,
    bot/player action confirmations, etc.) goes through this system instead of
    iPrintLnBold - the only exceptions are the welcome banner itself (not a
    feedback message) and the hitmarker/almost-hit/Trickshot Distance shot-feed
    (already its own separate, working system - see rainyAddBroadcastFeedEntry).
*/
rainyMsgStackBaseY()
{
    return -110;
}
rainyMsgStackLineGap()
{
    return 16;
}
rainyMsgStackMaxSlots()
{
    return 3;
}
rainyMsgStackHoldTimeMs()
{
    return 1500;
}
rainyMsgStackFadeTimeMs()
{
    return 350;
}
rainyMsgStackSlotY(slot)
{
    // Index 0 always holds the NEWEST message (rainyShowRaisedMessage writes the
    // newest entry to array index 0 every time, and array index lines up 1:1
    // with HUD slot index in rainyRenderMsgStackSlots). The newest message must
    // land exactly at baseY/-110, right above "Rainy's" - the same spot
    // confirmed correct back when this only ever showed one message at a time.
    // So slot 0 = baseY, full stop, regardless of maxSlots. Each older message
    // (higher slot index) then steps further UP and away from the banner by one
    // gap (more-negative Y is higher up the screen here - see the welcome
    // banner's own -88 placement).
    return rainyMsgStackBaseY() - (slot * rainyMsgStackLineGap());
}
rainyEnsureMsgStackSlots()
{
    if (isDefined(level.rainyLevelShuttingDown) && level.rainyLevelShuttingDown)
        return;
    if (isDefined(self.rainyMsgStackHuds) && self.rainyMsgStackHuds.size >= rainyMsgStackMaxSlots())
        return;

    self.rainyMsgStackHuds = [];
    for (i = 0; i < rainyMsgStackMaxSlots(); i++)
    {
        hud = self createFontString("smallfixed", 1.0);
        hud setPoint("CENTER", "CENTER", 0, rainyMsgStackSlotY(i));
        hud.alpha = 0;
        hud.sort = 9999;
        hud.archived = false;
        hud.hideWhenInMenu = false;
        hud.foreground = true;
        hud.color = (1, 1, 1);
        hud.glowColor = (0.6, 0, 0.6);
        hud.glowAlpha = 0;
        hud set_text("");
        self.rainyMsgStackHuds[i] = hud;
    }
}
rainyCleanExpiredMsgStackEntries()
{
    if (!isDefined(self.rainyMsgStackMsgs) || !isDefined(self.rainyMsgStackTimes))
        return;

    now = getTime();
    maxAge = rainyMsgStackHoldTimeMs() + rainyMsgStackFadeTimeMs();

    cleanMsgs = [];
    cleanTimes = [];
    writeIndex = 0;
    for (i = 0; i < self.rainyMsgStackMsgs.size; i++)
    {
        if (!isDefined(self.rainyMsgStackMsgs[i]) || !isDefined(self.rainyMsgStackTimes[i]))
            continue;
        if (now - self.rainyMsgStackTimes[i] >= maxAge)
            continue;
        cleanMsgs[writeIndex] = self.rainyMsgStackMsgs[i];
        cleanTimes[writeIndex] = self.rainyMsgStackTimes[i];
        writeIndex++;
    }
    self.rainyMsgStackMsgs = cleanMsgs;
    self.rainyMsgStackTimes = cleanTimes;
}
rainyMsgStackAlphaForEntry(entryTime)
{
    if (!isDefined(entryTime))
        return 0;

    age = getTime() - entryTime;
    holdMs = rainyMsgStackHoldTimeMs();
    fadeMs = rainyMsgStackFadeTimeMs();

    if (age < holdMs)
        return 1.0;
    if (age >= holdMs + fadeMs)
        return 0;

    alpha = 1.0 - (((age - holdMs) * 1.0) / fadeMs);
    if (alpha < 0)
        alpha = 0;
    if (alpha > 1)
        alpha = 1;
    return alpha;
}
rainyRenderMsgStackSlots()
{
    if (isDefined(level.rainyLevelShuttingDown) && level.rainyLevelShuttingDown)
        return;

    self rainyEnsureMsgStackSlots();
    if (!isDefined(self.rainyMsgStackHuds))
        return;

    for (i = 0; i < rainyMsgStackMaxSlots(); i++)
    {
        hud = self.rainyMsgStackHuds[i];
        if (!isDefined(hud))
            continue;
        // Position is set once at creation in rainyEnsureMsgStackSlots and never
        // touched again here - only text/alpha change per refresh. Re-calling
        // setPoint on every render is what caused the old "flies in" glitch.
        if (isDefined(self.rainyMsgStackMsgs) && isDefined(self.rainyMsgStackMsgs[i]))
        {
            alpha = 1.0;
            if (isDefined(self.rainyMsgStackTimes) && isDefined(self.rainyMsgStackTimes[i]))
                alpha = rainyMsgStackAlphaForEntry(self.rainyMsgStackTimes[i]);
            hud set_text(self.rainyMsgStackMsgs[i]);
            hud.alpha = alpha;
            hud.glowAlpha = 0.48 * alpha;
        }
        else
        {
            hud set_text("");
            hud.alpha = 0;
            hud.glowAlpha = 0;
        }
    }
}
rainyMsgStackFadeLoop()
{
    self endon("disconnect");
    self endon("rainy_msg_stack_shutdown");
    level endon("rainy_shutdown");

    while (true)
    {
        self rainyCleanExpiredMsgStackEntries();
        self rainyRenderMsgStackSlots();

        if (!isDefined(self.rainyMsgStackMsgs) || self.rainyMsgStackMsgs.size <= 0)
        {
            self.rainyMsgStackFadeLoopRunning = false;
            return;
        }
        wait 0.05;
    }
}
rainyTeardownMsgStackHud()
{
    // Mirrors rainyTeardownBroadcastHud() exactly (same notify -> flag -> queue
    // clear -> HUD destroy loop -> undefine pattern). Without this, the raised
    // message stack's HUD elements (created in rainyEnsureMsgStackSlots) were
    // never destroyed on menu teardown/game end/disconnect - only the broadcast
    // feed had a matching teardown function. Leftover client HUD elements here
    // are the same class of risk that motivated rainyTeardownBroadcastHud.
    self notify("rainy_msg_stack_shutdown");
    self.rainyMsgStackFadeLoopRunning = false;
    self.rainyMsgStackMsgs = [];
    self.rainyMsgStackTimes = [];

    if (isDefined(self.rainyMsgStackHuds))
    {
        for (i = 0; i < self.rainyMsgStackHuds.size; i++)
        {
            if (isDefined(self.rainyMsgStackHuds[i]))
                self.rainyMsgStackHuds[i] destroy();
        }
    }

    self.rainyMsgStackHuds = undefined;
}
rainyShowRaisedMessage(msg)
{
    self endon("disconnect");
    level endon("rainy_shutdown");

    if (isDefined(level.rainyLevelShuttingDown) && level.rainyLevelShuttingDown)
        return;

    self rainyEnsureMsgStackSlots();
    self rainyCleanExpiredMsgStackEntries();

    if (!isDefined(self.rainyMsgStackMsgs))
        self.rainyMsgStackMsgs = [];
    if (!isDefined(self.rainyMsgStackTimes))
        self.rainyMsgStackTimes = [];

    maxSlots = rainyMsgStackMaxSlots();
    oldMsgs = self.rainyMsgStackMsgs;
    oldTimes = self.rainyMsgStackTimes;

    newMsgs = [];
    newTimes = [];

    // Newest entry always occupies index 0 (rendered in the bottom-most slot via
    // rainyMsgStackSlotY); existing entries shift up by index only - the HUD
    // elements themselves never move, matching rainyAddBroadcastFeedEntry.
    newMsgs[0] = msg;
    newTimes[0] = getTime();

    writeIndex = 1;
    for (i = 0; i < oldMsgs.size && writeIndex < maxSlots; i++)
    {
        if (!isDefined(oldMsgs[i]))
            continue;
        newMsgs[writeIndex] = oldMsgs[i];
        newTimes[writeIndex] = oldTimes[i];
        writeIndex++;
    }

    self.rainyMsgStackMsgs = newMsgs;
    self.rainyMsgStackTimes = newTimes;

    self rainyRenderMsgStackSlots();

    if (!isDefined(self.rainyMsgStackFadeLoopRunning) || !self.rainyMsgStackFadeLoopRunning)
    {
        self.rainyMsgStackFadeLoopRunning = true;
        self thread rainyMsgStackFadeLoop();
    }
}

persistentHudMenuControls()
{
    self endon("disconnect");
    level endon("game_ended");
    level endon("rainy_shutdown");
    // Only the host may open/operate the on-screen menu. Non-host players still keep
    // their own keybinds (save/load position, and canswap when the host enables it for
    // them) because those run in separate threads - saveLoadBindMonitor and
    // canswapBindMonitor - not in here. This function governs ONLY menu navigation and
    // open/close, so returning early for non-hosts removes their menu access without
    // disabling any of their binds.
    if (!self isHost())
        return;
    self thread rainyMenuCloseOnDeath();
    self notifyonplayercommand("ts_menu_up", "+actionslot 1");
    self notifyonplayercommand("ts_menu_up", "+nightvision");
    self notifyonplayercommand("ts_menu_up", "+scores");
    self notifyonplayercommand("ts_menu_down", "+actionslot 2");
    self thread menuScrollUpListener();
    self thread menuScrollDownListener();
    for (;;)
    {
        adsNow = self adsButtonPressed();
        meleeNow = self meleeButtonPressed();
        useNow = self useButtonPressed();
        adsPressed = adsNow && !self.lastAdsState;
        meleePressed = meleeNow && !self.lastMeleeState;
        usePressed = useNow && !self.lastUseState;
        if (!self.menuOpen && adsNow && meleePressed)
        {
            self.menuOpen = true;
            if (!isDefined(self.menuPage) || self.menuPage == "")
                self.menuPage = "main";
            if (!isDefined(self.menuIndex))
                self.menuIndex = 0;
            self createMenuHud();
            self updateMenuHud();
            while (self adsButtonPressed() || self meleeButtonPressed())
                wait 0.05;
            self.lastAdsState = false;
            self.lastMeleeState = false;
            self.lastUseState = false;
        }
        else if (self.menuOpen && adsNow && meleePressed)
        {
            self.menuOpen = false;
            self destroyMenuHud();
            while (self adsButtonPressed() || self meleeButtonPressed())
                wait 0.05;
            self.lastAdsState = false;
            self.lastMeleeState = false;
            self.lastUseState = false;
        }
        else if (self.menuOpen)
        {
            if (meleePressed && !adsNow)
            {
                if (isDefined(self.menuPage) && self.menuPage == "snipers")
                {
                    self.menuPage = "giveweapons";
                    self.menuIndex = 0;
                    self updateMenuHud();
                }
                else if (isDefined(self.menuPage) && self.menuPage == "handguns")
                {
                    self.menuPage = "giveweapons";
                    self.menuIndex = 1;
                    self updateMenuHud();
                }
                else if (isDefined(self.menuPage) && self.menuPage == "shotguns")
                {
                    self.menuPage = "giveweapons";
                    self.menuIndex = 2;
                    self updateMenuHud();
                }
                else if (isDefined(self.menuPage) && self.menuPage == "machinepistols")
                {
                    self.menuPage = "giveweapons";
                    self.menuIndex = 3;
                    self updateMenuHud();
                }
                else if (isDefined(self.menuPage) && self.menuPage == "assaultrifles")
                {
                    self.menuPage = "giveweapons";
                    self.menuIndex = 4;
                    self updateMenuHud();
                }
                else if (isDefined(self.menuPage) && self.menuPage == "smgs")
                {
                    self.menuPage = "giveweapons";
                    self.menuIndex = 5;
                    self updateMenuHud();
                }
                else if (isDefined(self.menuPage) && self.menuPage == "lmgs")
                {
                    self.menuPage = "giveweapons";
                    self.menuIndex = 6;
                    self updateMenuHud();
                }
                else if (isDefined(self.menuPage) && self.menuPage == "giveweapons")
                {
                    self.menuPage = "weapons";
                    self.menuIndex = 0;
                    self updateMenuHud();
                }
                else if (isDefined(self.menuPage) && self.menuPage == "attachments")
                {
                    self.menuPage = "weapons";
                    self.menuIndex = 1;
                    self updateMenuHud();
                }
                else if (isDefined(self.menuPage) && self.menuPage == "killstreaks")
                {
                    self.menuPage = "weapons";
                    self.menuIndex = 2;
                    self updateMenuHud();
                }
                else if (isDefined(self.menuPage) && self.menuPage == "killstreaks2")
                {
                    self.menuPage = "killstreaks";
                    self.menuIndex = 9;
                    self updateMenuHud();
                }
                else if (isDefined(self.menuPage) && self.menuPage == "fun")
                {
                    self.menuPage = "main";
                    self.menuIndex = 4;
                    self updateMenuHud();
                }
                else if (isDefined(self.menuPage) && self.menuPage == "spawnables")
                {
                    self.menuPage = "trickshotmods";
                    self.menuIndex = 4;
                    self updateMenuHud();
                }
                else if (isDefined(self.menuPage) && self.menuPage == "trickshotmods")
                {
                    self.menuPage = "mainmods";
                    self.menuIndex = 0;
                    self updateMenuHud();
                }
                else if (isDefined(self.menuPage) && self.menuPage == "trickshotmods2")
                {
                    self.menuPage = "trickshotmods";
                    self.menuIndex = 9;
                    self updateMenuHud();
                }
                else if (isDefined(self.menuPage) && self.menuPage == "clients")
                {
                    self.menuPage = "main";
                    self.menuIndex = 6;
                    self updateMenuHud();
                }
                else if (isDefined(self.menuPage) && self.menuPage == "allplayers")
                {
                    prevPage = 0;
                    if (isDefined(self.clientsPage)) prevPage = self.clientsPage;
                    self rainyOpenClientsMenuPage(prevPage);
                    self.menuIndex = self.clientsMenuLastIdx;
                    self updateMenuHud();
                }
                else if (isDefined(self.menuPage) && self.menuPage == "allplayers2")
                {
                    // Knife-back from page 2 goes one page back to page 1,
                    // same as every other paginated submenu in the menu.
                    self.menuPage = "allplayers";
                    self.menuIndex = 9;
                    self updateMenuHud();
                }
                else if (isDefined(self.menuPage) && isSubStr(self.menuPage, "clientsub_"))
                {
                    // Rebuild the page we came from (player list may have changed)
                    prevPage = 0;
                    if (isDefined(self.clientsPage)) prevPage = self.clientsPage;
                    self rainyOpenClientsMenuPage(prevPage);
                    self.menuIndex = self.clientsMenuLastIdx;
                    self updateMenuHud();
                }
                else if (isDefined(self.menuPage) && isSubStr(self.menuPage, "clientsub2_"))
                {
                    // Knife-back from page 2 goes one page back to page 1
                    // for the SAME target player, same as every other
                    // paginated submenu in the menu - it should not jump
                    // all the way back to the clients list.
                    target2knifeback = self.clientSubTarget;
                    self.menuPage = "clientsub_" + target2knifeback getEntityNumber();
                    self.menuIndex = 9;
                    self updateMenuHud();
                }
                else if (isDefined(self.menuPage) && self.menuPage == "visions")
                {
                    self.menuPage = "fun";
                    self.menuIndex = 0;
                    self updateMenuHud();
                }
                else if (isDefined(self.menuPage) && self.menuPage == "visions2")
                {
                    self.menuPage = "visions";
                    self.menuIndex = 9;
                    self updateMenuHud();
                }
                else if (isDefined(self.menuPage) && self.menuPage == "visions3")
                {
                    self.menuPage = "visions2";
                    self.menuIndex = 9;
                    self updateMenuHud();
                }
                else if (isDefined(self.menuPage) && self.menuPage == "visions4")
                {
                    self.menuPage = "visions3";
                    self.menuIndex = 9;
                    self updateMenuHud();
                }
                else if (isDefined(self.menuPage) && self.menuPage == "visions5")
                {
                    self.menuPage = "visions4";
                    self.menuIndex = 9;
                    self updateMenuHud();
                }
                else if (isDefined(self.menuPage) && self.menuPage == "perkhub")
                {
                    self.menuPage = "weapons";
                    self.menuIndex = 3;
                    self updateMenuHud();
                }
                else if (isDefined(self.menuPage) && self.menuPage == "givecamo")
                {
                    self.menuPage = "weapons";
                    self.menuIndex = 4;
                    self updateMenuHud();
                }
                else if (isDefined(self.menuPage) && self.menuPage == "giveperks")
                {
                    self.menuPage = "perkhub";
                    self.menuIndex = 2;
                    self updateMenuHud();
                }
                else if (isDefined(self.menuPage) && self.menuPage == "giveperks2")
                {
                    self.menuPage = "giveperks";
                    self.menuIndex = 9;
                    self updateMenuHud();
                }
                else if (isDefined(self.menuPage) && self.menuPage == "takeperks")
                {
                    self.menuPage = "perkhub";
                    self.menuIndex = 3;
                    self updateMenuHud();
                }
                else if (isDefined(self.menuPage) && self.menuPage == "takeperks2")
                {
                    self.menuPage = "takeperks";
                    self.menuIndex = 9;
                    self updateMenuHud();
                }
                else if (isDefined(self.menuPage) && self.menuPage == "specials")
                {
                    self.menuPage = "giveweapons";
                    self.menuIndex = 7;
                    self updateMenuHud();
                }
                else if (isDefined(self.menuPage) && self.menuPage == "launchers")
                {
                    self.menuPage = "specials";
                    self.menuIndex = 1;
                    self updateMenuHud();
                }
                else if (isDefined(self.menuPage) && self.menuPage == "lethals")
                {
                    self.menuPage = "giveweapons";
                    self.menuIndex = 8;
                    self updateMenuHud();
                }
                else if (isDefined(self.menuPage) && self.menuPage == "tacticals")
                {
                    self.menuPage = "giveweapons";
                    self.menuIndex = 9;
                    self updateMenuHud();
                }
                else if (isDefined(self.menuPage) && self.menuPage == "settime")
                {
                    self.menuPage = "lobby";
                    self.menuIndex = 0;
                    self updateMenuHud();
                }
                else if (isDefined(self.menuPage) && self.menuPage == "setgamemode")
                {
                    self.menuPage = "lobby";
                    self.menuIndex = 3;
                    self updateMenuHud();
                }
                else if (isDefined(self.menuPage) && self.menuPage == "setscore")
                {
                    self.menuPage = "lobby";
                    self.menuIndex = 4;
                    self updateMenuHud();
                }
                else if (isDefined(self.menuPage) && self.menuPage == "ffascore")
                {
                    self.menuPage = "setscore";
                    self.menuIndex = 0;
                    self updateMenuHud();
                }
                else if (isDefined(self.menuPage) && self.menuPage == "tdmscore")
                {
                    self.menuPage = "setscore";
                    self.menuIndex = 1;
                    self updateMenuHud();
                }
                else if (isDefined(self.menuPage) && self.menuPage == "tdmoptions")
                {
                    self.menuPage = "lobby";
                    self.menuIndex = 5;
                    self updateMenuHud();
                }
                else if (isDefined(self.menuPage) && self.menuPage == "teamsdifficulty")
                {
                    self.menuPage = "bots";
                    self.menuIndex = 4;
                    self updateMenuHud();
                }
                else if (isDefined(self.menuPage) && self.menuPage == "addbots")
                {
                    self.menuPage = "bots";
                    self.menuIndex = 0;
                    self updateMenuHud();
                }
                else if (isDefined(self.menuPage) && self.menuPage != "main")
                {
                    self.menuPage = "main";
                    self.menuIndex = 0;
                    self updateMenuHud();
                }
                else
                {
                    self closeMenuHud();
                }
                wait 0.12;
            }
            else if (usePressed && !adsNow && !meleeNow)
            {
                self menuSelect();
                wait 0.18;
            }
        }
        self.lastAdsState = adsNow;
        self.lastMeleeState = meleeNow;
        self.lastUseState = useNow;
        wait 0.03;
    }
}
menuScrollUpListener()
{
    self endon("disconnect");
    level endon("game_ended");
    level endon("rainy_shutdown");
    for (;;)
    {
        self waittill("ts_menu_up");
        if (!isDefined(self.menuOpen) || !self.menuOpen)
        {
            if (self GetStance() == "prone")
            {
                self toggleAutoRefillAmmo();
                wait 0.5;
            }
            continue;
        }
        self.menuIndex--;
        if (self.menuIndex < 0)
            self.menuIndex = self getMenuMaxIndex();
        self updateMenuHud();
        wait 0.15;
    }
}
menuScrollDownListener()
{
    self endon("disconnect");
    level endon("game_ended");
    level endon("rainy_shutdown");
    for (;;)
    {
        self waittill("ts_menu_down");
        if (!isDefined(self.menuOpen) || !self.menuOpen)
            continue;
        self.menuIndex++;
        if (self.menuIndex > self getMenuMaxIndex())
            self.menuIndex = 0;
        self updateMenuHud();
        wait 0.15;
    }
}
createTrickshotMenuRect(width, height, color, alpha, x, y, sort)
{
    rect = newClientHudElem(self);
    rect.elemType = "rect";
    rect.x = 0;
    rect.y = 0;
    rect.xOffset = 0;
    rect.yOffset = 0;
    rect.width = width;
    rect.height = height;
    rect.baseWidth = width;
    rect.baseHeight = height;
    rect.color = color;
    rect.alpha = alpha;
    rect.children = [];
    rect maps\mp\gametypes\_hud_util::setParent(level.uiParent);
    rect.hidden = false;
    rect.archived = false;
    rect.foreground = true;
    rect.sort = sort;
    rect setShader("white", int(width), int(height));
    rect.shader = "white";
    rect setPoint("TOP_LEFT", "TOP_RIGHT", x - rainyMenuRightRef(), y);
    return rect;
}
createTrickshotMenuShaderRect(width, height, shader, color, alpha, x, y, sort)
{
    rect = newClientHudElem(self);
    rect.elemType = "rect";
    rect.x = 0;
    rect.y = 0;
    rect.xOffset = 0;
    rect.yOffset = 0;
    rect.width = width;
    rect.height = height;
    rect.baseWidth = width;
    rect.baseHeight = height;
    rect.color = color;
    rect.alpha = alpha;
    rect.children = [];
    rect maps\mp\gametypes\_hud_util::setParent(level.uiParent);
    rect.hidden = false;
    rect.archived = false;
    rect.foreground = true;
    rect.sort = sort;
    rect setShader(shader, int(width), int(height));
    rect.shader = shader;
    rect setPoint("TOP_LEFT", "TOPCENTER", x, y);
    return rect;
}
createRainyMenuShader(shader, width, height, alpha, x, y, sort)
{
    hud = newClientHudElem(self);
    hud.horzAlign = "center";
    hud.vertAlign = "top";
    hud.alignX = "center";
    hud.alignY = "top";
    hud.x = x;
    hud.y = y;
    hud.width = width;
    hud.height = height;
    hud.color = (1.0, 1.0, 1.0);
    hud.alpha = alpha;
    hud.sort = sort;
    hud.foreground = true;
    hud.archived = false;
    hud setShader(shader, int(width), int(height));
    return hud;
}
rainyMenuRightRef()
{
    // Half of the HUD's virtual width at the 16:9 reference the menu was authored on
    // (virtual height 480 * 16/9 / 2 = 426.67). Every menu element's X was laid out as
    // an offset measured rightward from screen CENTER. Subtracting this value rebases
    // that X into an offset measured leftward from the screen's RIGHT edge. Combined with
    // anchoring each element to the right edge (a "..._RIGHT" relativePoint), the menu
    // lands in the exact same spot it always did on 16:9 and stays pinned to the right
    // edge on every other aspect ratio / resolution - the engine resolves where the right
    // edge actually is per client at render time, so no per-client math is needed (and
    // none is possible from server-created HUD elements anyway).
    return 426.67;
}
createMenuHud()
{
    if (isDefined(level.rainyLevelShuttingDown) && level.rainyLevelShuttingDown)
        return;

    self destroyMenuHud();
    self notify("rainy_menu_closed");
    // Hand the feed's client-HUD slots to the menu BEFORE allocating any menu element, so
    // the menu builds into the freed pool. Without this the feed's slots are still held at
    // creation time and, after a killcam, the last menu element (the header line) loses the
    // allocation race. menuOpen is already true here, so the feed will not rebuild until
    // the menu closes (guard in rainyEnsureBroadcastSlots).
    self rainyReleaseBroadcastSlotsForMenu();
    self.menuX = 157;
    self.menuY = 82;
    self.menuRowSpacing = 27;
    // Allocate the essential elements FIRST (backdrop, then all text rows, then the
    // select bar). MW2/IW4x has a hard client HUD-element cap; when it is near-full
    // (notably at game end with the end-game scoreboard up) the LAST createFontString
    // calls silently fail to get a slot. By creating entries before decoration, any
    // shortfall drops only cosmetic pieces - never a visible menu row.
    self.menuHudBackdrop = self createTrickshotMenuRect(250, 480, (0.018, 0.014, 0.040), 0.88, self.menuX - 24, 0, 100);
    self.menuHud0 = self createMenuText("", self.menuX + 24, self.menuY + 82, 0.82);
    self.menuHud1 = self createMenuText("", self.menuX + 24, self.menuY + 109, 0.82);
    self.menuHud2 = self createMenuText("", self.menuX + 24, self.menuY + 136, 0.82);
    self.menuHud3 = self createMenuText("", self.menuX + 24, self.menuY + 163, 0.82);
    self.menuHud4 = self createMenuText("", self.menuX + 24, self.menuY + 190, 0.82);
    self.menuHud5 = self createMenuText("", self.menuX + 24, self.menuY + 217, 0.82);
    self.menuHud6 = self createMenuText("", self.menuX + 24, self.menuY + 244, 0.82);
    self.menuHud7 = self createMenuText("", self.menuX + 24, self.menuY + 271, 0.82);
    self.menuHud8 = self createMenuText("", self.menuX + 24, self.menuY + 298, 0.82);
    self.menuHud9 = self createMenuText("", self.menuX + 24, self.menuY + 325, 0.82);
    self.menuHudSelectBar = self createTrickshotMenuRect(228, 23, (0.28, 0.12, 0.62), 0.85, self.menuX - 14, self.menuY + 70, 105);
    // Prestige skull selector. Created HERE (with the essential elements), not dead last.
    // All menu elements share one client HUD-element pool, and after a respawn the pool is
    // a hair tighter (the base game's post-spawn HUD), so whatever was created LAST was the
    // one starved of a slot - and the skull was last. Moving it up to just after the select
    // bar guarantees it gets a slot before the purely-decorative rails do. The spin loop
    // re-points it to the hovered row each frame; here we just place it on row 0 to start.
    self.menuHudSelectTick = createIcon("white", 28, 28);
    self.menuHudSelectTick.color = (1.0, 1.0, 1.0);
    self.menuHudSelectTick.alpha = 1.0;
    self.menuHudSelectTick.foreground = true;
    self.menuHudSelectTick.archived = false;
    self.menuHudSelectTick.sort = 9998;
    self.menuHudSelectTick setShader("cardicon_prestige10_02", 28, 28);
    self.menuHudSelectTick setPoint("LEFT", "TOP_RIGHT", (self.menuX - 4) - rainyMenuRightRef(), self.menuY + 82);
    self.menuHudTitle = self createMenuTextFont("^5Rainy^7's ^7Mod ^5Menu ^7v^71", self.menuX + 5, self.menuY + 2, 1.06, "smallfixed", 9999);
    self.menuHudTitle.color = (1.0, 1.0, 1.0);
    self.menuHudTitle.glowColor = (0.03, 0.38, 0.92);
    self.menuHudTitle.glowAlpha = 0.75;
    self.menuHudPageLabel = self createMenuTextFont(":: MAIN MENU", self.menuX + 23, self.menuY + 52, 0.72, "smallfixed", 9999);
    self.menuHudPageLabel.color = (0.72, 0.52, 1.00);
    self.menuHudTitleGlow = self createMenuTextFont("^7[^5 Created ^7by^5 Rainy City ^7]", self.menuX + 14, self.menuY + 27, 0.64, "smallfixed", 9999);
    self.menuHudTitleGlow.color = (1.0, 1.0, 1.0);
    self.menuHudTitleGlow.glowColor = (0.10, 0.20, 0.70);
    self.menuHudTitleGlow.glowAlpha = 0.45;
    // Cosmetic-only elements last (rails, separators, skull tick). Safe to drop if
    // the HUD pool is exhausted - they never carry menu entry text.
    self.menuHudLeftRail = self createTrickshotMenuRect(5, 480, (0.55, 0.18, 1.00), 0.55, self.menuX - 24, 0, 103);
    // Right rail is kept fully inside the same dark panel edge as the left rail.
    // This makes the transparency/readability match the left rail instead of bleeding over the world view.
    self.menuHudRightRail = self createTrickshotMenuRect(5, 480, (0.55, 0.18, 1.00), 0.55, self.menuX + 221, 0, 103);
    self.menuHudHeaderLine = self createTrickshotMenuRect(240, 2, (0.55, 0.18, 1.00), 0.64, self.menuX - 19, self.menuY + 43, 104);
    // (The prestige skull selector is created earlier - right after the select bar - so it
    // is allocated alongside the essential elements and is never the one dropped.)
    self thread menuTitleCursorLoop();
    self thread menuSelectBarPulse();
}
createMenuText(text, x, y, scale)
{
    hud = self createFontString("smallfixed", scale);
    hud setPoint("LEFT", "TOP_RIGHT", x - rainyMenuRightRef(), y);
    hud.alpha = 1;
    hud.sort = 9999;
    hud.archived = false;
    hud.hideWhenInMenu = false;
    hud.color = (0.86, 0.88, 1.00);
    hud.glowColor = (0.20, 0.12, 0.50);
    hud.glowAlpha = 0.24;
    hud set_text(text);
    return hud;
}
createMenuTextFont(text, x, y, scale, font, sort)
{
    hud = self createFontString(font, scale);
    hud setPoint("TOP_LEFT", "TOP_RIGHT", x - rainyMenuRightRef(), y);
    hud.alpha = 1;
    hud.sort = sort;
    hud.archived = false;
    hud.hideWhenInMenu = false;
    hud.color = (0.82, 0.84, 1.00);
    hud.glowColor = (0.24, 0.14, 0.55);
    hud.glowAlpha = 0.25;
    hud set_text(text);
    return hud;
}
menuTitleCursorLoop()
{
    self endon("disconnect");
    level endon("game_ended");
    level endon("rainy_shutdown");
    self endon("rainy_menu_closed");
    for (;;)
    {
        if (!isDefined(self.menuHudTitle))
            return;
        self.menuHudTitle set_text("^5Rainy^7's ^7Mod ^5Menu ^7v^71 ^5_");
        wait 1.05;
        if (!isDefined(self.menuHudTitle))
            return;
        self.menuHudTitle set_text("^5Rainy^7's ^7Mod ^5Menu ^7v^71");
        wait 1.05;
    }
}
menuSelectBarPulse()
{
    self endon("disconnect");
    level endon("game_ended");
    level endon("rainy_shutdown");
    self endon("rainy_menu_closed");
    for (;;)
    {
        if (!isDefined(self.menuHudSelectBar))
            return;
        self.menuHudSelectBar fadeOverTime(0.6);
        self.menuHudSelectBar.alpha = 0.95;
        for (i = 0; i < 20; i++)
        {
            self updatePrestigeSelectorSpin();
            wait 0.03;
        }
        if (!isDefined(self.menuHudSelectBar))
            return;
        self.menuHudSelectBar fadeOverTime(0.9);
        self.menuHudSelectBar.alpha = 0.55;
        for (i = 0; i < 30; i++)
        {
            self updatePrestigeSelectorSpin();
            wait 0.03;
        }
    }
}
updatePrestigeSelectorSpin()
{
    if (!isDefined(self.menuHudSelectTick))
        return;

    // Pin the skull to the hovered row using the same row geometry/anchor the rows use,
    // so it stays correctly beside the selection at any resolution. menuY+82 is row 0's
    // vertical center; each row is menuRowSpacing apart.
    iconY = self.menuY + 82 + (self.menuIndex * self.menuRowSpacing);
    self.menuHudSelectTick setPoint("LEFT", "TOP_RIGHT", (self.menuX - 4) - rainyMenuRightRef(), iconY);
    self.menuHudSelectTick.alpha = 1.0;

    // Selected-row text color. Change selectedColor to (1.0, 0.5, 0.0) for orange.
    selectedColor = (1.0, 0.82, 0.0);
    defaultColor  = (0.86, 0.88, 1.00);
    rows = [];
    rows[0] = self.menuHud0;
    rows[1] = self.menuHud1;
    rows[2] = self.menuHud2;
    rows[3] = self.menuHud3;
    rows[4] = self.menuHud4;
    rows[5] = self.menuHud5;
    rows[6] = self.menuHud6;
    rows[7] = self.menuHud7;
    rows[8] = self.menuHud8;
    rows[9] = self.menuHud9;
    for (i = 0; i < rows.size; i++)
    {
        if (!isDefined(rows[i]))
            continue;
        if (isDefined(rows[i].rainySelfColored) && rows[i].rainySelfColored)
            continue;                                     // text has its own embedded
                                                            // colors (set_text already
                                                            // set the correct element
                                                            // color) - never repaint it
        if (i == self.menuIndex)
            rows[i].color = selectedColor;               // gold on the hovered row
        else if (isDefined(rows[i].rainyRowColor))
            rows[i].color = rows[i].rainyRowColor;        // cyan/white stripe
        else
            rows[i].color = defaultColor;
    }
}
getMenuPageLabel()
{
    if (!isDefined(self.menuPage))
        return "MAIN MENU";
    if (self.menuPage == "main") return "MAIN MENU";
    if (self.menuPage == "aimbot") return "AIMBOT OPTIONS";
    if (self.menuPage == "mainmods") return "MAIN MODS";
    if (self.menuPage == "bots") return "BOT OPTIONS";
    if (self.menuPage == "teamsdifficulty") return "TEAMS AND DIFFICULTY";
    if (self.menuPage == "addbots") return "ADD BOTS";
    if (self.menuPage == "lobby") return "LOBBY OPTIONS";
    if (self.menuPage == "setgamemode") return "SET GAMEMODE";
    if (self.menuPage == "tdmoptions") return "TDM OPTIONS";
    if (self.menuPage == "settime") return "SET TIME";
    if (self.menuPage == "setscore") return "SET SCORE";
    if (self.menuPage == "ffascore") return "SET FFA SCORE";
    if (self.menuPage == "tdmscore") return "SET TDM SCORE";
    if (self.menuPage == "weapons") return "GIVE OPTIONS";
    if (self.menuPage == "givecamo") return "GIVE CAMO";
    if (self.menuPage == "giveweapons") return "GIVE WEAPONS";
    if (self.menuPage == "snipers") return "SNIPER RIFLES";
    if (self.menuPage == "handguns") return "HANDGUNS";
    if (self.menuPage == "shotguns") return "SHOTGUNS";
    if (self.menuPage == "machinepistols") return "MACHINE PISTOLS";
    if (self.menuPage == "assaultrifles") return "ASSAULT RIFLES";
    if (self.menuPage == "smgs") return "SUBMACHINE GUNS";
    if (self.menuPage == "lmgs") return "LIGHT MACHINE GUNS";
    if (self.menuPage == "specials") return "SPECIALS";
    if (self.menuPage == "launchers") return "LAUNCHERS";
    if (self.menuPage == "lethals") return "LETHALS";
    if (self.menuPage == "tacticals") return "TACTICALS";
    if (self.menuPage == "attachments") return "ATTACHMENTS";
    if (self.menuPage == "killstreaks") return "ADD KILLSTREAKS";
    if (self.menuPage == "fun") return "FUN MODS";
    if (self.menuPage == "spawnables") return "SPAWNABLES";
    if (self.menuPage == "trickshotmods") return "TRICKSHOT MODS";
    if (self.menuPage == "trickshotmods2") return "TRICKSHOT MODS";
    if (self.menuPage == "clients") return "PLAYER OPTIONS";
    if (self.menuPage == "allplayers") return "ALL PLAYERS";
    if (self.menuPage == "allplayers2") return "ALL PLAYERS";
    if (isSubStr(self.menuPage, "clientsub_")) return self.clientSubTitle;
    if (isSubStr(self.menuPage, "clientsub2_")) return self.clientSubTitle;
    if (self.menuPage == "visions") return "VISIONS";
    if (self.menuPage == "visions2") return "VISIONS";
    if (self.menuPage == "visions3") return "VISIONS";
    if (self.menuPage == "visions4") return "VISIONS";
    if (self.menuPage == "visions5") return "VISIONS";
    if (self.menuPage == "perkhub") return "GIVE PERKS";
    if (self.menuPage == "giveperks") return "GIVE PERKS";
    if (self.menuPage == "giveperks2") return "GIVE PERKS";
    if (self.menuPage == "takeperks") return "TAKE PERKS";
    if (self.menuPage == "takeperks2") return "TAKE PERKS";
    if (self.menuPage == "killstreaks2") return "ADD KILLSTREAKS";
    return "MENU";
}
getMenuMaxIndex()
{
    if (!isDefined(self.menuPage))
        self.menuPage = "main";
    if (self.menuPage == "main")
        return 6;
    if (self.menuPage == "clients")
        return self.clientsMenuMax;
    if (self.menuPage == "allplayers")
        return 9;
    if (self.menuPage == "allplayers2")
        return 3;
    if (isSubStr(self.menuPage, "clientsub_"))
    {
        // All 10 items always render and are selectable, for both bots and
        // real players. The 3 player-only items (Auto Refill Ammo, Fast Last
        // FFA, Give TS Aimbot) each guard themselves at the function level
        // (rainyToggleClientAutoRefill/rainyClientFastLast/
        // rainyToggleClientTsAimbot all print "Not available for bots" and
        // bail) rather than being hidden here, since their bot-incompatible
        // slots sit between bot-compatible ones (Teleport, Freeze, etc.) in
        // the order this menu mirrors from All Players, so there's no single
        // contiguous range left to gate at the menu level anymore.
        return 9;
    }
    if (isSubStr(self.menuPage, "clientsub2_"))
        return 3;
    if (self.menuPage == "fun")
        return 4;
    if (self.menuPage == "trickshotmods")
        return 9;
    if (self.menuPage == "trickshotmods2")
        return 3;
    if (self.menuPage == "spawnables")
        return 4;
    if (self.menuPage == "visions") return 9;
    if (self.menuPage == "visions2") return 9;
    if (self.menuPage == "visions3") return 9;
    if (self.menuPage == "visions4") return 9;
    if (self.menuPage == "visions5") return 8;
    if (self.menuPage == "aimbot")
        return 5;
    if (self.menuPage == "mainmods")
        return 7;
    if (self.menuPage == "bots")
        return 9;
    if (self.menuPage == "teamsdifficulty")
        return 5;
    if (self.menuPage == "addbots")
        return 4;
    if (self.menuPage == "weapons")
        return 7;
    if (self.menuPage == "givecamo")
    {
        if (!isDefined(self.camoCount) || self.camoCount == 0)
            return 0;
        return self.camoCount - 1;
    }
    if (self.menuPage == "perkhub")
        return 3;
    if (self.menuPage == "giveperks")
        return 9;
    if (self.menuPage == "giveperks2")
        return 7;
    if (self.menuPage == "takeperks")
        return 9;
    if (self.menuPage == "takeperks2")
        return 7;
    if (self.menuPage == "killstreaks")
        return 9;
    if (self.menuPage == "killstreaks2")
        return 7;
    if (self.menuPage == "giveweapons")
        return 9;
    if (self.menuPage == "snipers")
        return 5;
    if (self.menuPage == "handguns")
        return 4;
    if (self.menuPage == "shotguns")
        return 5;
    if (self.menuPage == "machinepistols")
        return 3;
    if (self.menuPage == "assaultrifles")
        return 9;
    if (self.menuPage == "smgs")
        return 6;
    if (self.menuPage == "lmgs")
        return 4;
    if (self.menuPage == "specials")
        return 1;
    if (self.menuPage == "launchers")
        return 4;
    if (self.menuPage == "lethals")
        return 4;
    if (self.menuPage == "tacticals")
        return 2;
    if (self.menuPage == "attachments")
    {
        if (!isDefined(self.attachCount) || self.attachCount == 0)
            return 0;
        return self.attachCount - 1;
    }
    if (self.menuPage == "lobby")
        return 7;
    if (self.menuPage == "setgamemode")
        return 2;
    if (self.menuPage == "tdmoptions")
        return 4;
    if (self.menuPage == "settime")
        return 3;
    if (self.menuPage == "setscore")
        return 1;
    if (self.menuPage == "ffascore")
        return 3;
    if (self.menuPage == "tdmscore")
        return 3;
    return 2;
}
updateMenuHud()
{
    if (!isDefined(self.menuHud0))
        return;
    if (!isDefined(self.menuPage))
        self.menuPage = "main";
    if (self.menuIndex > self getMenuMaxIndex())
        self.menuIndex = 0;
    selectorY = self.menuY + 70 + (self.menuIndex * self.menuRowSpacing);
    if (isDefined(self.menuHudSelectBar))
        self.menuHudSelectBar setPoint("TOP_LEFT", "TOP_RIGHT", (self.menuX - 14) - rainyMenuRightRef(), selectorY);
    if (isDefined(self.menuHudSelectTick))
        self updatePrestigeSelectorSpin();
    if (isDefined(self.menuHudPageLabel))
    {
        self.menuHudPageLabel.color = (0.72, 0.52, 1.00);
        self.menuHudPageLabel set_text(":: " + self getMenuPageLabel());
    }
    botCombatStatus = "^5ON";
    botCombatPlain = "ON";
    chatStatus = "^5OFF";
    chatPlain = "OFF";
    difficultyStatus = "^5" + botSkillLabel(getDvarInt("bots_skill"));
    difficultyPlain = botSkillLabel(getDvarInt("bots_skill"));
    botTeamStatus = "^5" + botTeamLabel(getDvar("bots_team"));
    botTeamPlain = botTeamLabel(getDvar("bots_team"));
    axisBotCountStatus = "^5" + getDvarInt("bots_team_amount");
    axisBotCountPlain = "" + getDvarInt("bots_team_amount");
    forceBotTeamStatus = "^5OFF";
    forceBotTeamPlain = "OFF";
    if (getDvarInt("bots_team_force") != 0)
    {
        forceBotTeamStatus = "^5ON";
        forceBotTeamPlain = "ON";
    }
    botTeamTargetStatus = "^5" + botTeamModeLabel(getDvarInt("bots_team_mode"));
    botTeamTargetPlain = botTeamModeLabel(getDvarInt("bots_team_mode"));
    forceUavStatus = "^5OFF";
    forceUavPlain = "OFF";
    ufoStatus = "^5OFF";
    ufoPlain = "OFF";
    godStatus = "^5OFF";
    godPlain = "OFF";
    killcamStatus = "^5OFF";
    killcamPlain = "OFF";
    speedStatus = "^51x";
    speedPlain = "1x";
    gravityStatus = "^51x";
    gravityPlain = "1x";
    fovStatus = "^565";
    fovPlain = "65";
    if (isDefined(self.godMode) && self.godMode)
    {
        godStatus = "^5ON";
        godPlain = "ON";
    }
    if (isDefined(self.rainyKillcamsEnabled) && self.rainyKillcamsEnabled)
    {
        killcamStatus = "^5ON";
        killcamPlain = "ON";
    }
    if (isDefined(level.passiveBotsActive) && level.passiveBotsActive)
    {
        botCombatStatus = "^5OFF";
        botCombatPlain = "OFF";
    }
    if (getDvarFloat("bots_main_chat") > 0)
    {
        chatStatus = "^5ON";
        chatPlain = "ON";
    }
    if (isDefined(level.forceUAV) && level.forceUAV)
    {
        forceUavStatus = "^5ON";
        forceUavPlain = "ON";
    }
    if (isDefined(self.ufoEnabled) && self.ufoEnabled)
    {
        ufoStatus = "^5ON";
        ufoPlain = "ON";
    }
    if (isDefined(self.playerSpeedLevel))
    {
        if (self.playerSpeedLevel == 2)      { speedStatus = "^52x";  speedPlain = "2x"; }
        else if (self.playerSpeedLevel == 3) { speedStatus = "^53x";  speedPlain = "3x"; }
        else if (self.playerSpeedLevel == 4) { speedStatus = "^54x";  speedPlain = "4x"; }
        else if (self.playerSpeedLevel == 5) { speedStatus = "^55x";  speedPlain = "5x"; }
        else if (self.playerSpeedLevel == 6) { speedStatus = "^510x"; speedPlain = "10x"; }
        else                                  { speedStatus = "^51x";  speedPlain = "1x"; }
    }
    if (isDefined(self.gravityLevel))
    {
        if (self.gravityLevel == 2)       { gravityStatus = "^52x";  gravityPlain = "2x"; }
        else if (self.gravityLevel == 3)  { gravityStatus = "^53x";  gravityPlain = "3x"; }
        else if (self.gravityLevel == 4)  { gravityStatus = "^54x";  gravityPlain = "4x"; }
        else if (self.gravityLevel == 5)  { gravityStatus = "^55x";  gravityPlain = "5x"; }
        else if (self.gravityLevel == 6)  { gravityStatus = "^56x";  gravityPlain = "6x"; }
        else if (self.gravityLevel == 7)  { gravityStatus = "^57x";  gravityPlain = "7x"; }
        else if (self.gravityLevel == 8)  { gravityStatus = "^58x";  gravityPlain = "8x"; }
        else if (self.gravityLevel == 9)  { gravityStatus = "^59x";  gravityPlain = "9x"; }
        else if (self.gravityLevel == 10) { gravityStatus = "^510x"; gravityPlain = "10x"; }
        else                                { gravityStatus = "^51x";  gravityPlain = "1x"; }
    }
    if (isDefined(self.rainyFovLevel))
    {
        if (self.rainyFovLevel == 2)      { fovStatus = "^580";  fovPlain = "80"; }
        else if (self.rainyFovLevel == 3) { fovStatus = "^590";  fovPlain = "90"; }
        else if (self.rainyFovLevel == 4) { fovStatus = "^5100"; fovPlain = "100"; }
        else if (self.rainyFovLevel == 5) { fovStatus = "^5110"; fovPlain = "110"; }
        else                                { fovStatus = "^565";  fovPlain = "65"; }
    }
    healthStatus = "^5Normal";
    healthPlain = "Normal";
    if (isDefined(level.healthLevel))
    {
        if (level.healthLevel == 2)      { healthStatus = "^5Half";      healthPlain = "Half"; }
        else if (level.healthLevel == 3) { healthStatus = "^5Miniscule"; healthPlain = "Miniscule"; }
        else if (level.healthLevel == 4) { healthStatus = "^51HP";       healthPlain = "1HP"; }
        else if (level.healthLevel == 5) { healthStatus = "^5Double";    healthPlain = "Double"; }
        else                               { healthStatus = "^5Normal";   healthPlain = "Normal"; }
    }
    trickshotDamageOnlyStatus = "^5OFF";
    trickshotDamageOnlyPlain = "OFF";
    if (isDefined(level.trickshotDamageOnly) && level.trickshotDamageOnly)
    {
        trickshotDamageOnlyStatus = "^5ON";
        trickshotDamageOnlyPlain = "ON";
    }
    friendlyFireStatus = "^5OFF";
    friendlyFirePlain = "OFF";
    if (isDefined(level.rainyFriendlyFire) && level.rainyFriendlyFire)
    {
        friendlyFireStatus = "^5ON";
        friendlyFirePlain = "ON";
    }
    tpStatus = "^5OFF";
    tpPlain = "OFF";
    if (getDvarInt("camera_thirdPerson") == 1) { tpStatus = "^5ON"; tpPlain = "ON"; }
    wallbangStatus   = "^5OFF";
    wallbangPlain    = "OFF";
    wbSnapStatus     = "^5OFF";
    wbSnapPlain      = "OFF";
    tsAimbotStatus   = "^5OFF";
    tsAimbotPlain    = "OFF";
    silentAimStatus  = "^5OFF";
    silentAimPlain   = "OFF";
    snapAimStatus    = "^5OFF";
    snapAimPlain     = "OFF";
    unfairAimbotStatus = "^5OFF";
    unfairAimbotPlain  = "OFF";
    if (isDefined(self.wallbangOn)   && self.wallbangOn)   { wallbangStatus  = "^5ON"; wallbangPlain  = "ON"; }
    if (isDefined(self.wallbangSnapOn) && self.wallbangSnapOn) { wbSnapStatus = "^5ON"; wbSnapPlain = "ON"; }
    if (isDefined(self.tsAimbotOn)   && self.tsAimbotOn)   { tsAimbotStatus  = "^5ON"; tsAimbotPlain  = "ON"; }
    if (isDefined(self.silentAimOn)  && self.silentAimOn)  { silentAimStatus = "^5ON"; silentAimPlain = "ON"; }
    if (isDefined(self.snapAimOn)    && self.snapAimOn)    { snapAimStatus   = "^5ON"; snapAimPlain   = "ON"; }
    if (isDefined(self.unfairAimbotOn) && self.unfairAimbotOn) { unfairAimbotStatus = "^5ON"; unfairAimbotPlain = "ON"; }
    self.menuHud0 set_text("");
    self.menuHud1 set_text("");
    self.menuHud2 set_text("");
    self.menuHud3 set_text("");
    self.menuHud4 set_text("");
    self.menuHud5 set_text("");
    self.menuHud6 set_text("");
    self.menuHud7 set_text("");
    self.menuHud8 set_text("");
    self.menuHud9 set_text("");
    if (self.menuPage == "main")
    {
        if (self.menuIndex == 0)
            self.menuHud0 set_text("   Main Mods");
        else
            self.menuHud0 set_text("^5  Main ^7Mods");
        if (self.menuIndex == 1)
            self.menuHud1 set_text("   Lobby Options");
        else
            self.menuHud1 set_text("^5  Lobby ^7Options");
        if (self.menuIndex == 2)
            self.menuHud2 set_text("   Bot Options");
        else
            self.menuHud2 set_text("^5  Bot ^7Options");
        if (self.menuIndex == 3)
            self.menuHud3 set_text("   Give Options");
        else
            self.menuHud3 set_text("^5  Give ^7Options");
        if (self.menuIndex == 4)
            self.menuHud4 set_text("   Fun Mods");
        else
            self.menuHud4 set_text("^5  Fun ^7Mods");
        if (self.menuIndex == 5)
            self.menuHud5 set_text("   Aimbot Options");
        else
            self.menuHud5 set_text("^5  Aimbot ^7Options");
        if (self.menuIndex == 6)
            self.menuHud6 set_text("   Player Options");
        else
            self.menuHud6 set_text("^5  Player ^7Options");
        return;
    }
    if (self.menuPage == "clients")
    {
        self rainyBuildClientsRender();
        return;
    }
    if (self.menuPage == "allplayers")
    {
        allRefillStatus = "^5OFF";
        allRefillPlain = "OFF";
        if (isDefined(level.rainyAllAutoRefill) && level.rainyAllAutoRefill)
        {
            allRefillStatus = "^5ON";
            allRefillPlain = "ON";
        }
        if (self.menuIndex == 0)
            self.menuHud0 set_text("   All Auto Refill Ammo [" + allRefillPlain + "]");
        else
            self.menuHud0 set_text("^5  All Auto Refill Ammo ^7[" + allRefillStatus + "^7]");
        if (self.menuIndex == 1)
            self.menuHud1 set_text("   Fast Last All FFA");
        else
            self.menuHud1 set_text("^7  Fast Last All FFA");
        if (self.menuIndex == 2)
            self.menuHud2 set_text("   Teleport All to Me");
        else
            self.menuHud2 set_text("^5  Teleport All to Me");
        if (self.menuIndex == 3)
            self.menuHud3 set_text("   Teleport All to Crosshair");
        else
            self.menuHud3 set_text("^7  Teleport All to Crosshair");
        allTsAimbotStatus = "^5OFF";
        allTsAimbotPlain = "OFF";
        if (isDefined(level.rainyAllTsAimbot) && level.rainyAllTsAimbot)
        {
            allTsAimbotStatus = "^5ON";
            allTsAimbotPlain = "ON";
        }
        if (self.menuIndex == 4)
            self.menuHud4 set_text("   Give All TS Aimbot [" + allTsAimbotPlain + "]");
        else
            self.menuHud4 set_text("^5  Give All TS Aimbot ^7[" + allTsAimbotStatus + "^7]");
        if (self.menuIndex == 5)
            self.menuHud5 set_text("   Freeze All");
        else
            self.menuHud5 set_text("^7  Freeze All");
        if (self.menuIndex == 6)
            self.menuHud6 set_text("   Unfreeze All");
        else
            self.menuHud6 set_text("^5  Unfreeze All");
        if (self.menuIndex == 7)
            self.menuHud7 set_text("   Kick All");
        else
            self.menuHud7 set_text("^7  Kick All");
        if (self.menuIndex == 8)
            self.menuHud8 set_text("   Kill All");
        else
            self.menuHud8 set_text("^5  Kill All");
        if (self.menuIndex == 9)
            self.menuHud9 set_text("   Page 2 ->");
        else
            self.menuHud9 set_text("^7  Page 2 ^5->");
        return;
    }
    if (self.menuPage == "allplayers2")
    {
        allGodStatus = "^5OFF";
        allGodPlain = "OFF";
        if (isDefined(level.rainyAllGodMode) && level.rainyAllGodMode)
        {
            allGodStatus = "^5ON";
            allGodPlain = "ON";
        }
        if (self.menuIndex == 0)
            self.menuHud0 set_text("   All God Mode [" + allGodPlain + "]");
        else
            self.menuHud0 set_text("^5  All God Mode ^7[" + allGodStatus + "^7]");
        if (self.menuIndex == 1)
            self.menuHud1 set_text("   Reset All FFA Score");
        else
            self.menuHud1 set_text("^7  Reset All FFA Score");
        allCanswapStatus = "^5OFF";
        allCanswapPlain = "OFF";
        if (isDefined(level.rainyAllCanswap) && level.rainyAllCanswap)
        {
            allCanswapStatus = "^5ON";
            allCanswapPlain = "ON";
        }
        if (self.menuIndex == 2)
            self.menuHud2 set_text("   Canswap Bind All [" + allCanswapPlain + "]");
        else
            self.menuHud2 set_text("^5  Canswap Bind All ^7[" + allCanswapStatus + "^7]");
        if (self.menuIndex == 3)
            self.menuHud3 set_text("   Page 1 <-");
        else
            self.menuHud3 set_text("^7  Page 1 ^5<-");
        return;
    }
    if (isSubStr(self.menuPage, "clientsub_"))
    {
        cTarget = self.clientSubTarget;

        cRefillStatus = "^5OFF";
        cRefillPlain = "OFF";
        if (isDefined(cTarget) && isDefined(cTarget.rainyAutoRefillAmmo) && cTarget.rainyAutoRefillAmmo)
        {
            cRefillStatus = "^5ON";
            cRefillPlain = "ON";
        }
        if (self.menuIndex == 0)
            self.menuHud0 set_text("   Auto Refill Ammo [" + cRefillPlain + "]");
        else
            self.menuHud0 set_text("^5  Auto Refill Ammo ^7[" + cRefillStatus + "^7]");

        if (self.menuIndex == 1)
            self.menuHud1 set_text("   Fast Last FFA");
        else
            self.menuHud1 set_text("^7  Fast Last FFA");

        if (self.menuIndex == 2)
            self.menuHud2 set_text("   Teleport to Me");
        else
            self.menuHud2 set_text("^5  Teleport to Me");

        if (self.menuIndex == 3)
            self.menuHud3 set_text("   Teleport to Crosshair");
        else
            self.menuHud3 set_text("^7  Teleport to Crosshair");

        cTsAimbotStatus = "^5OFF";
        cTsAimbotPlain = "OFF";
        if (isDefined(cTarget) && isDefined(cTarget.tsAimbotOn) && cTarget.tsAimbotOn)
        {
            cTsAimbotStatus = "^5ON";
            cTsAimbotPlain = "ON";
        }
        if (self.menuIndex == 4)
            self.menuHud4 set_text("   Give TS Aimbot [" + cTsAimbotPlain + "]");
        else
            self.menuHud4 set_text("^5  Give TS Aimbot ^7[" + cTsAimbotStatus + "^7]");

        if (self.menuIndex == 5)
            self.menuHud5 set_text("   Freeze Player");
        else
            self.menuHud5 set_text("^7  Freeze Player");

        if (self.menuIndex == 6)
            self.menuHud6 set_text("   Unfreeze Player");
        else
            self.menuHud6 set_text("^5  Unfreeze Player");

        if (self.menuIndex == 7)
            self.menuHud7 set_text("   Kick Player");
        else
            self.menuHud7 set_text("^7  Kick Player");

        if (self.menuIndex == 8)
            self.menuHud8 set_text("   Kill Player");
        else
            self.menuHud8 set_text("^5  Kill Player");

        if (self.menuIndex == 9)
            self.menuHud9 set_text("   Page 2 ->");
        else
            self.menuHud9 set_text("^7  Page 2 ^5->");
        return;
    }
    if (isSubStr(self.menuPage, "clientsub2_"))
    {
        cTarget2 = self.clientSubTarget;
        cGodStatus = "^5OFF";
        cGodPlain = "OFF";
        if (isDefined(cTarget2) && isDefined(cTarget2.godMode) && cTarget2.godMode)
        {
            cGodStatus = "^5ON";
            cGodPlain = "ON";
        }
        if (self.menuIndex == 0)
            self.menuHud0 set_text("   God Mode [" + cGodPlain + "]");
        else
            self.menuHud0 set_text("^5  God Mode ^7[" + cGodStatus + "^7]");

        if (self.menuIndex == 1)
            self.menuHud1 set_text("   Reset FFA Score");
        else
            self.menuHud1 set_text("^7  Reset FFA Score");

        cCanswapStatus2 = "^5OFF";
        cCanswapPlain2 = "OFF";
        if (isDefined(cTarget2) && isDefined(cTarget2.canswapBound) && cTarget2.canswapBound)
        {
            cCanswapStatus2 = "^5ON";
            cCanswapPlain2 = "ON";
        }
        if (self.menuIndex == 2)
            self.menuHud2 set_text("   Canswap Bind [" + cCanswapPlain2 + "]");
        else
            self.menuHud2 set_text("^5  Canswap Bind ^7[" + cCanswapStatus2 + "^7]");

        if (self.menuIndex == 3)
            self.menuHud3 set_text("   Page 1 <-");
        else
            self.menuHud3 set_text("^7  Page 1 ^5<-");
        return;
    }
    if (self.menuPage == "fun")
    {
        if (self.menuIndex == 0)
            self.menuHud0 set_text("   Visions >>");
        else
            self.menuHud0 set_text("^5  Visions >>");
        if (self.menuIndex == 1)
            self.menuHud1 set_text("   Third Person [" + tpPlain + "]");
        else
            self.menuHud1 set_text("^7  Third Person ^7[" + tpStatus + "^7]");
        if (self.menuIndex == 2)
            self.menuHud2 set_text("   Speed [" + speedPlain + "]");
        else
            self.menuHud2 set_text("^5  Speed ^7[" + speedStatus + "^7]");
        if (self.menuIndex == 3)
            self.menuHud3 set_text("   Super Jump [" + gravityPlain + "]");
        else
            self.menuHud3 set_text("^7  Super Jump ^7[" + gravityStatus + "^7]");
        if (self.menuIndex == 4)
            self.menuHud4 set_text("   Change FOV [" + fovPlain + "]");
        else
            self.menuHud4 set_text("^5  Change FOV ^7[" + fovStatus + "^7]");
        return;
    }
    if (self.menuPage == "trickshotmods")
    {
        autoRefillStatus = "^5OFF";
        autoRefillPlain = "OFF";
        if (isDefined(self.rainyAutoRefillAmmo) && self.rainyAutoRefillAmmo)
        {
            autoRefillStatus = "^5ON";
            autoRefillPlain = "ON";
        }
        if (self.menuIndex == 0)
            self.menuHud0 set_text("   Auto Refill Ammo [" + autoRefillPlain + "]");
        else
            self.menuHud0 set_text("^5  Auto Refill Ammo ^7[" + autoRefillStatus + "^7]");
        if (self.menuIndex == 1)
            self.menuHud1 set_text("   Fast Last FFA");
        else
            self.menuHud1 set_text("^7  Fast Last FFA");
        if (self.menuIndex == 2)
            self.menuHud2 set_text("   Fast Last TDM");
        else
            self.menuHud2 set_text("^5  Fast Last TDM");
        if (self.menuIndex == 3)
            self.menuHud3 set_text("   Reset Score FFA");
        else
            self.menuHud3 set_text("^7  Reset Score FFA");
        if (self.menuIndex == 4)
            self.menuHud4 set_text("   Spawnables >>");
        else
            self.menuHud4 set_text("^5  Spawnables >>");

        infiniteCareStatus = "^5OFF";
        infiniteCarePlain = "OFF";
        if (isDefined(self.rainyInfiniteCarePackage) && self.rainyInfiniteCarePackage)
        {
            infiniteCareStatus = "^5ON";
            infiniteCarePlain = "ON";
        }
        if (self.menuIndex == 5)
            self.menuHud5 set_text("   Infinite Care Package [" + infiniteCarePlain + "]");
        else
            self.menuHud5 set_text("^7  Infinite Care Package ^7[" + infiniteCareStatus + "^7]");

        forgeStatus = "^5OFF";
        forgePlain = "OFF";
        if (isDefined(self.rainyForgeMode) && self.rainyForgeMode)
        {
            forgeStatus = "^5ON";
            forgePlain = "ON";
        }
        if (self.menuIndex == 6)
            self.menuHud6 set_text("   Forge Mode [" + forgePlain + "]");
        else
            self.menuHud6 set_text("^5  Forge Mode ^7[" + forgeStatus + "^7]");

        noCollisionStatus = "^5OFF";
        noCollisionPlain = "OFF";
        if (isDefined(level.rainyNoPlayerCollision) && level.rainyNoPlayerCollision)
        {
            noCollisionStatus = "^5ON";
            noCollisionPlain = "ON";
        }
        if (self.menuIndex == 7)
            self.menuHud7 set_text("   No Player Collision [" + noCollisionPlain + "]");
        else
            self.menuHud7 set_text("^7  No Player Collision ^7[" + noCollisionStatus + "^7]");

        canswapStatus = "^5OFF";
        canswapPlain = "OFF";
        if (isDefined(self.canswapBound) && self.canswapBound)
        {
            canswapStatus = "^5ON";
            canswapPlain = "ON";
        }
        if (self.menuIndex == 8)
            self.menuHud8 set_text("   Canswap Bind [" + canswapPlain + "]");
        else
            self.menuHud8 set_text("^5  Canswap Bind ^7[" + canswapStatus + "^7]");

        if (self.menuIndex == 9) self.menuHud9 set_text("   Page 2 ->");
        else                     self.menuHud9 set_text("^7  Page 2 ^5->");
        return;
    }
    if (self.menuPage == "trickshotmods2")
    {
        tsPlatformBindStatus = "^5ON";
        tsPlatformBindPlain = "ON";
        if (isDefined(self.rainyTsPlatformBindOn) && !self.rainyTsPlatformBindOn)
        {
            tsPlatformBindStatus = "^5OFF";
            tsPlatformBindPlain = "OFF";
        }
        if (self.menuIndex == 0)
            self.menuHud0 set_text("   TS Platform Bind [" + tsPlatformBindPlain + "]");
        else
            self.menuHud0 set_text("^5  TS Platform Bind ^7[" + tsPlatformBindStatus + "^7]");
        tsDistStatus = "^5ON";
        tsDistPlain = "ON";
        if (isDefined(self.trickshotDistanceOn) && !self.trickshotDistanceOn)
        {
            tsDistStatus = "^5OFF";
            tsDistPlain = "OFF";
        }
        if (self.menuIndex == 1)
            self.menuHud1 set_text("   Trickshot Distance [" + tsDistPlain + "]");
        else
            self.menuHud1 set_text("^7  Trickshot Distance ^7[" + tsDistStatus + "^7]");
        almostHitsStatus = "^5ON";
        almostHitsPlain = "ON";
        if (isDefined(self.almostHitsOn) && !self.almostHitsOn)
        {
            almostHitsStatus = "^5OFF";
            almostHitsPlain = "OFF";
        }
        if (self.menuIndex == 2)
            self.menuHud2 set_text("   Almost Hits [" + almostHitsPlain + "]");
        else
            self.menuHud2 set_text("^5  Almost Hits ^7[" + almostHitsStatus + "^7]");
        if (self.menuIndex == 3) self.menuHud3 set_text("   Page 1 <-");
        else                     self.menuHud3 set_text("^7  Page 1 ^5<-");
        return;
    }
    if (self.menuPage == "spawnables")
    {
        if (self.menuIndex == 0)
            self.menuHud0 set_text("   Spawn Trickshot Platform");
        else
            self.menuHud0 set_text("^5  Spawn Trickshot Platform");
        if (self.menuIndex == 1)
            self.menuHud1 set_text("   Spawn Platform At Crosshair");
        else
            self.menuHud1 set_text("^7  Spawn Platform At Crosshair");
        if (self.menuIndex == 2)
            self.menuHud2 set_text("   Spawn Package");
        else
            self.menuHud2 set_text("^5  Spawn Package");
        if (self.menuIndex == 3)
            self.menuHud3 set_text("   Spawn Package At Crosshair");
        else
            self.menuHud3 set_text("^7  Spawn Package At Crosshair");
        if (self.menuIndex == 4)
            self.menuHud4 set_text("   Remove All Platforms");
        else
            self.menuHud4 set_text("^5  Remove All Platforms");
        return;
    }
    if (self.menuPage == "aimbot")
    {
        if (self.menuIndex == 0)
            self.menuHud0 set_text("   TS Aimbot [" + tsAimbotPlain + "]");
        else
            self.menuHud0 set_text("^5  TS Aimbot ^7[" + tsAimbotStatus + "^7]");
        if (self.menuIndex == 1)
            self.menuHud1 set_text("   Wallbang Everything [" + wallbangPlain + "]");
        else
            self.menuHud1 set_text("^7  Wallbang Everything ^7[" + wallbangStatus + "^7]");
        if (self.menuIndex == 2)
            self.menuHud2 set_text("   Wallbang + Snap Aim [" + wbSnapPlain + "]");
        else
            self.menuHud2 set_text("^5  Wallbang + Snap Aim ^7[" + wbSnapStatus + "^7]");
        if (self.menuIndex == 3)
            self.menuHud3 set_text("   Silent Aim [" + silentAimPlain + "]");
        else
            self.menuHud3 set_text("^7  Silent Aim ^7[" + silentAimStatus + "^7]");
        if (self.menuIndex == 4)
            self.menuHud4 set_text("   Snap Aim [" + snapAimPlain + "]");
        else
            self.menuHud4 set_text("^5  Snap Aim ^7[" + snapAimStatus + "^7]");
        if (self.menuIndex == 5)
            self.menuHud5 set_text("   Unfair Aimbot [" + unfairAimbotPlain + "]");
        else
            self.menuHud5 set_text("^7  Unfair Aimbot ^7[" + unfairAimbotStatus + "^7]");
        return;
    }
    if (self.menuPage == "weapons")
    {
        if (self.menuIndex == 0)
            self.menuHud0 set_text("   Give Weapons >>");
        else
            self.menuHud0 set_text("^5  Give Weapons >>");
        if (self.menuIndex == 1)
            self.menuHud1 set_text("   Give Attachments >>");
        else
            self.menuHud1 set_text("^7  Give Attachments >>");
        if (self.menuIndex == 2)
            self.menuHud2 set_text("   Give Killstreaks >>");
        else
            self.menuHud2 set_text("^5  Give Killstreaks >>");
        if (self.menuIndex == 3)
            self.menuHud3 set_text("   Give Perks >>");
        else
            self.menuHud3 set_text("^7  Give Perks >>");
        if (self.menuIndex == 4)
            self.menuHud4 set_text("   Give Camo >>");
        else
            self.menuHud4 set_text("^5  Give Camo >>");
        if (self.menuIndex == 5)
            self.menuHud5 set_text("   Delete Current Weapon");
        else
            self.menuHud5 set_text("^7  Delete Current Weapon");
        if (self.menuIndex == 6)
            self.menuHud6 set_text("   Take Ground Weapon");
        else
            self.menuHud6 set_text("^5  Take Ground Weapon");
        if (self.menuIndex == 7)
            self.menuHud7 set_text("   Drop Current Weapon");
        else
            self.menuHud7 set_text("^7  Drop Current Weapon");
        return;
    }
    if (self.menuPage == "givecamo")
    {
        if (!isDefined(self.camoCount) || self.camoCount == 0)
        {
            self.menuHud0 set_text("^1No camos available");
            return;
        }
        if (isDefined(self.camo0))
        {
            if (self.menuIndex == 0) self.menuHud0 set_text("   " + self.camo0);
            else self.menuHud0 set_text("^5  " + self.camo0);
        }
        if (isDefined(self.camo1))
        {
            if (self.menuIndex == 1) self.menuHud1 set_text("   " + self.camo1);
            else self.menuHud1 set_text("^7  " + self.camo1);
        }
        if (isDefined(self.camo2))
        {
            if (self.menuIndex == 2) self.menuHud2 set_text("   " + self.camo2);
            else self.menuHud2 set_text("^5  " + self.camo2);
        }
        if (isDefined(self.camo3))
        {
            if (self.menuIndex == 3) self.menuHud3 set_text("   " + self.camo3);
            else self.menuHud3 set_text("^7  " + self.camo3);
        }
        if (isDefined(self.camo4))
        {
            if (self.menuIndex == 4) self.menuHud4 set_text("   " + self.camo4);
            else self.menuHud4 set_text("^5  " + self.camo4);
        }
        if (isDefined(self.camo5))
        {
            if (self.menuIndex == 5) self.menuHud5 set_text("   " + self.camo5);
            else self.menuHud5 set_text("^7  " + self.camo5);
        }
        if (isDefined(self.camo6))
        {
            if (self.menuIndex == 6) self.menuHud6 set_text("   " + self.camo6);
            else self.menuHud6 set_text("^5  " + self.camo6);
        }
        if (isDefined(self.camo7))
        {
            if (self.menuIndex == 7) self.menuHud7 set_text("   " + self.camo7);
            else self.menuHud7 set_text("^7  " + self.camo7);
        }
        if (isDefined(self.camo8))
        {
            if (self.menuIndex == 8) self.menuHud8 set_text("   " + self.camo8);
            else self.menuHud8 set_text("^5  " + self.camo8);
        }
        if (isDefined(self.camo9))
        {
            if (self.menuIndex == 9) self.menuHud9 set_text("   " + self.camo9);
            else self.menuHud9 set_text("^7  " + self.camo9);
        }
        return;
    }
    if (self.menuPage == "perkhub")
    {
        if (self.menuIndex == 0) self.menuHud0 set_text("   Give All Perks");
        else                     self.menuHud0 set_text("^5  Give All Perks");
        if (self.menuIndex == 1) self.menuHud1 set_text("   Take All Perks");
        else                     self.menuHud1 set_text("^7  Take All Perks");
        if (self.menuIndex == 2) self.menuHud2 set_text("   Give Perks >>");
        else                     self.menuHud2 set_text("^5  Give Perks >>");
        if (self.menuIndex == 3) self.menuHud3 set_text("   Take Perks >>");
        else                     self.menuHud3 set_text("^7  Take Perks >>");
        return;
    }
    if (self.menuPage == "giveperks")
    {
        if (self.menuIndex == 0) self.menuHud0 set_text("   Marathon Pro");
        else                     self.menuHud0 set_text("^5  Marathon Pro");
        if (self.menuIndex == 1) self.menuHud1 set_text("   Sleight of Hand Pro");
        else                     self.menuHud1 set_text("^7  Sleight of Hand Pro");
        if (self.menuIndex == 2) self.menuHud2 set_text("   Scavenger Pro");
        else                     self.menuHud2 set_text("^5  Scavenger Pro");
        if (self.menuIndex == 3) self.menuHud3 set_text("   Bling Pro");
        else                     self.menuHud3 set_text("^7  Bling Pro");
        if (self.menuIndex == 4) self.menuHud4 set_text("   One Man Army Pro");
        else                     self.menuHud4 set_text("^5  One Man Army Pro");
        if (self.menuIndex == 5) self.menuHud5 set_text("   Stopping Power Pro");
        else                     self.menuHud5 set_text("^7  Stopping Power Pro");
        if (self.menuIndex == 6) self.menuHud6 set_text("   Lightweight Pro");
        else                     self.menuHud6 set_text("^5  Lightweight Pro");
        if (self.menuIndex == 7) self.menuHud7 set_text("   Hardline Pro");
        else                     self.menuHud7 set_text("^7  Hardline Pro");
        if (self.menuIndex == 8) self.menuHud8 set_text("   Cold-Blooded Pro");
        else                     self.menuHud8 set_text("^5  Cold-Blooded Pro");
        if (self.menuIndex == 9) self.menuHud9 set_text("   Page 2 ->");
        else                     self.menuHud9 set_text("^7  Page 2 ^5->");
        return;
    }
    if (self.menuPage == "giveperks2")
    {
        if (self.menuIndex == 0) self.menuHud0 set_text("   Danger Close Pro");
        else                     self.menuHud0 set_text("^5  Danger Close Pro");
        if (self.menuIndex == 1) self.menuHud1 set_text("   Commando Pro");
        else                     self.menuHud1 set_text("^7  Commando Pro");
        if (self.menuIndex == 2) self.menuHud2 set_text("   Steady Aim Pro");
        else                     self.menuHud2 set_text("^5  Steady Aim Pro");
        if (self.menuIndex == 3) self.menuHud3 set_text("   Scrambler Pro");
        else                     self.menuHud3 set_text("^7  Scrambler Pro");
        if (self.menuIndex == 4) self.menuHud4 set_text("   Ninja Pro");
        else                     self.menuHud4 set_text("^5  Ninja Pro");
        if (self.menuIndex == 5) self.menuHud5 set_text("   SitRep Pro");
        else                     self.menuHud5 set_text("^7  SitRep Pro");
        if (self.menuIndex == 6) self.menuHud6 set_text("   Last Stand Pro");
        else                     self.menuHud6 set_text("^5  Last Stand Pro");
        if (self.menuIndex == 7) self.menuHud7 set_text("   Page 1 <-");
        else                     self.menuHud7 set_text("^7  Page 1 ^5<-");
        return;
    }
    if (self.menuPage == "takeperks")
    {
        if (self.menuIndex == 0) self.menuHud0 set_text("   Marathon Pro");
        else                     self.menuHud0 set_text("^5  Marathon Pro");
        if (self.menuIndex == 1) self.menuHud1 set_text("   Sleight of Hand Pro");
        else                     self.menuHud1 set_text("^7  Sleight of Hand Pro");
        if (self.menuIndex == 2) self.menuHud2 set_text("   Scavenger Pro");
        else                     self.menuHud2 set_text("^5  Scavenger Pro");
        if (self.menuIndex == 3) self.menuHud3 set_text("   Bling Pro");
        else                     self.menuHud3 set_text("^7  Bling Pro");
        if (self.menuIndex == 4) self.menuHud4 set_text("   One Man Army Pro");
        else                     self.menuHud4 set_text("^5  One Man Army Pro");
        if (self.menuIndex == 5) self.menuHud5 set_text("   Stopping Power Pro");
        else                     self.menuHud5 set_text("^7  Stopping Power Pro");
        if (self.menuIndex == 6) self.menuHud6 set_text("   Lightweight Pro");
        else                     self.menuHud6 set_text("^5  Lightweight Pro");
        if (self.menuIndex == 7) self.menuHud7 set_text("   Hardline Pro");
        else                     self.menuHud7 set_text("^7  Hardline Pro");
        if (self.menuIndex == 8) self.menuHud8 set_text("   Cold-Blooded Pro");
        else                     self.menuHud8 set_text("^5  Cold-Blooded Pro");
        if (self.menuIndex == 9) self.menuHud9 set_text("   Page 2 ->");
        else                     self.menuHud9 set_text("^7  Page 2 ^5->");
        return;
    }
    if (self.menuPage == "takeperks2")
    {
        if (self.menuIndex == 0) self.menuHud0 set_text("   Danger Close Pro");
        else                     self.menuHud0 set_text("^5  Danger Close Pro");
        if (self.menuIndex == 1) self.menuHud1 set_text("   Commando Pro");
        else                     self.menuHud1 set_text("^7  Commando Pro");
        if (self.menuIndex == 2) self.menuHud2 set_text("   Steady Aim Pro");
        else                     self.menuHud2 set_text("^5  Steady Aim Pro");
        if (self.menuIndex == 3) self.menuHud3 set_text("   Scrambler Pro");
        else                     self.menuHud3 set_text("^7  Scrambler Pro");
        if (self.menuIndex == 4) self.menuHud4 set_text("   Ninja Pro");
        else                     self.menuHud4 set_text("^5  Ninja Pro");
        if (self.menuIndex == 5) self.menuHud5 set_text("   SitRep Pro");
        else                     self.menuHud5 set_text("^7  SitRep Pro");
        if (self.menuIndex == 6) self.menuHud6 set_text("   Last Stand Pro");
        else                     self.menuHud6 set_text("^5  Last Stand Pro");
        if (self.menuIndex == 7) self.menuHud7 set_text("   Page 1 <-");
        else                     self.menuHud7 set_text("^7  Page 1 ^5<-");
        return;
    }
    if (self.menuPage == "killstreaks")
    {
        if (self.menuIndex == 0) self.menuHud0 set_text("   Remove Killstreak");
        else                     self.menuHud0 set_text("^5  Remove Killstreak");
        if (self.menuIndex == 1) self.menuHud1 set_text("   UAV");
        else                     self.menuHud1 set_text("^7  UAV");
        if (self.menuIndex == 2) self.menuHud2 set_text("   Care Package");
        else                     self.menuHud2 set_text("^5  Care Package");
        if (self.menuIndex == 3) self.menuHud3 set_text("   Counter-UAV");
        else                     self.menuHud3 set_text("^7  Counter-UAV");
        if (self.menuIndex == 4) self.menuHud4 set_text("   Sentry Gun");
        else                     self.menuHud4 set_text("^5  Sentry Gun");
        if (self.menuIndex == 5) self.menuHud5 set_text("   Predator Missile");
        else                     self.menuHud5 set_text("^7  Predator Missile");
        if (self.menuIndex == 6) self.menuHud6 set_text("   Precision Airstrike");
        else                     self.menuHud6 set_text("^5  Precision Airstrike");
        if (self.menuIndex == 7) self.menuHud7 set_text("   Harrier Strike");
        else                     self.menuHud7 set_text("^7  Harrier Strike");
        if (self.menuIndex == 8) self.menuHud8 set_text("   Attack Helicopter");
        else                     self.menuHud8 set_text("^5  Attack Helicopter");
        if (self.menuIndex == 9) self.menuHud9 set_text("   Page 2 ->");
        else                     self.menuHud9 set_text("^7  Page 2 ^5->");
        return;
    }
    if (self.menuPage == "killstreaks2")
    {
        if (self.menuIndex == 0) self.menuHud0 set_text("   Emergency Airdrop");
        else                     self.menuHud0 set_text("^5  Emergency Airdrop");
        if (self.menuIndex == 1) self.menuHud1 set_text("   Pave Low");
        else                     self.menuHud1 set_text("^7  Pave Low");
        if (self.menuIndex == 2) self.menuHud2 set_text("   Stealth Bomber");
        else                     self.menuHud2 set_text("^5  Stealth Bomber");
        if (self.menuIndex == 3) self.menuHud3 set_text("   Chopper Gunner");
        else                     self.menuHud3 set_text("^7  Chopper Gunner");
        if (self.menuIndex == 4) self.menuHud4 set_text("   AC-130");
        else                     self.menuHud4 set_text("^5  AC-130");
        if (self.menuIndex == 5) self.menuHud5 set_text("   EMP");
        else                     self.menuHud5 set_text("^7  EMP");
        if (self.menuIndex == 6) self.menuHud6 set_text("   Tactical Nuke");
        else                     self.menuHud6 set_text("^5  Tactical Nuke");
        if (self.menuIndex == 7) self.menuHud7 set_text("   Page 1 <-");
        else                     self.menuHud7 set_text("^7  Page 1 ^5<-");
        return;
    }
    if (self.menuPage == "visions")
    {
        if (self.menuIndex == 0) self.menuHud0 set_text("   None");
        else                     self.menuHud0 set_text("^5  None");
        if (self.menuIndex == 1) self.menuHud1 set_text("   Fullbright");
        else                     self.menuHud1 set_text("^7  Fullbright");
        if (self.menuIndex == 2) self.menuHud2 set_text("   AC-130");
        else                     self.menuHud2 set_text("^5  AC-130");
        if (self.menuIndex == 3) self.menuHud3 set_text("   AC-130 Inverted");
        else                     self.menuHud3 set_text("^7  AC-130 Inverted");
        if (self.menuIndex == 4) self.menuHud4 set_text("   Aftermath");
        else                     self.menuHud4 set_text("^5  Aftermath");
        if (self.menuIndex == 5) self.menuHud5 set_text("   Airplane");
        else                     self.menuHud5 set_text("^7  Airplane");
        if (self.menuIndex == 6) self.menuHud6 set_text("   Airport");
        else                     self.menuHud6 set_text("^5  Airport");
        if (self.menuIndex == 7) self.menuHud7 set_text("   Airport Death");
        else                     self.menuHud7 set_text("^7  Airport Death");
        if (self.menuIndex == 8) self.menuHud8 set_text("   Airport Exterior");
        else                     self.menuHud8 set_text("^5  Airport Exterior");
        if (self.menuIndex == 9) self.menuHud9 set_text("   Page 2 ->");
        else                     self.menuHud9 set_text("^7  Page 2 ^5->");
        return;
    }
    if (self.menuPage == "visions2")
    {
        if (self.menuIndex == 0) self.menuHud0 set_text("   Airport Green");
        else                     self.menuHud0 set_text("^5  Airport Green");
        if (self.menuIndex == 1) self.menuHud1 set_text("   Airport Intro");
        else                     self.menuHud1 set_text("^7  Airport Intro");
        if (self.menuIndex == 2) self.menuHud2 set_text("   Airport Stairs");
        else                     self.menuHud2 set_text("^5  Airport Stairs");
        if (self.menuIndex == 3) self.menuHud3 set_text("   Ambush");
        else                     self.menuHud3 set_text("^7  Ambush");
        if (self.menuIndex == 4) self.menuHud4 set_text("   Armada");
        else                     self.menuHud4 set_text("^5  Armada");
        if (self.menuIndex == 5) self.menuHud5 set_text("   Armada Water");
        else                     self.menuHud5 set_text("^7  Armada Water");
        if (self.menuIndex == 6) self.menuHud6 set_text("   Big City Destroyed");
        else                     self.menuHud6 set_text("^5  Big City Destroyed");
        if (self.menuIndex == 7) self.menuHud7 set_text("   Blackout");
        else                     self.menuHud7 set_text("^7  Blackout");
        if (self.menuIndex == 8) self.menuHud8 set_text("   Blackout NVG");
        else                     self.menuHud8 set_text("^5  Blackout NVG");
        if (self.menuIndex == 9) self.menuHud9 set_text("   Page 3 ->");
        else                     self.menuHud9 set_text("^7  Page 3 ^5->");
        return;
    }
    if (self.menuPage == "visions3")
    {
        if (self.menuIndex == 0) self.menuHud0 set_text("   Bog");
        else                     self.menuHud0 set_text("^5  Bog");
        if (self.menuIndex == 1) self.menuHud1 set_text("   Boneyard");
        else                     self.menuHud1 set_text("^7  Boneyard");
        if (self.menuIndex == 2) self.menuHud2 set_text("   Bridge");
        else                     self.menuHud2 set_text("^5  Bridge");
        if (self.menuIndex == 3) self.menuHud3 set_text("   Cargo Ship");
        else                     self.menuHud3 set_text("^7  Cargo Ship");
        if (self.menuIndex == 4) self.menuHud4 set_text("   Cheat BW");
        else                     self.menuHud4 set_text("^5  Cheat BW");
        if (self.menuIndex == 5) self.menuHud5 set_text("   Cheat BW Contrast");
        else                     self.menuHud5 set_text("^7  Cheat BW Contrast");
        if (self.menuIndex == 6) self.menuHud6 set_text("   Cheat BW Invert");
        else                     self.menuHud6 set_text("^5  Cheat BW Invert");
        if (self.menuIndex == 7) self.menuHud7 set_text("   Cheat Chaplin Night");
        else                     self.menuHud7 set_text("^7  Cheat Chaplin Night");
        if (self.menuIndex == 8) self.menuHud8 set_text("   Cheat Contrast");
        else                     self.menuHud8 set_text("^5  Cheat Contrast");
        if (self.menuIndex == 9) self.menuHud9 set_text("   Page 4 ->");
        else                     self.menuHud9 set_text("^7  Page 4 ^5->");
        return;
    }
    if (self.menuPage == "visions4")
    {
        if (self.menuIndex == 0) self.menuHud0 set_text("   Cheat Invert");
        else                     self.menuHud0 set_text("^5  Cheat Invert");
        if (self.menuIndex == 1) self.menuHud1 set_text("   Cheat Invert Contrast");
        else                     self.menuHud1 set_text("^7  Cheat Invert Contrast");
        if (self.menuIndex == 2) self.menuHud2 set_text("   Cliff Hanger");
        else                     self.menuHud2 set_text("^5  Cliff Hanger");
        if (self.menuIndex == 3) self.menuHud3 set_text("   DC");
        else                     self.menuHud3 set_text("^7  DC");
        if (self.menuIndex == 4) self.menuHud4 set_text("   DC EMP");
        else                     self.menuHud4 set_text("^5  DC EMP");
        if (self.menuIndex == 5) self.menuHud5 set_text("   Default");
        else                     self.menuHud5 set_text("^7  Default");
        if (self.menuIndex == 6) self.menuHud6 set_text("   Default Night");
        else                     self.menuHud6 set_text("^5  Default Night");
        if (self.menuIndex == 7) self.menuHud7 set_text("   Default Night MP");
        else                     self.menuHud7 set_text("^7  Default Night MP");
        if (self.menuIndex == 8) self.menuHud8 set_text("   End Game");
        else                     self.menuHud8 set_text("^5  End Game");
        if (self.menuIndex == 9) self.menuHud9 set_text("   Page 5 ->");
        else                     self.menuHud9 set_text("^7  Page 5 ^5->");
        return;
    }
    if (self.menuPage == "visions5")
    {
        if (self.menuIndex == 0) self.menuHud0 set_text("   Intro Screen");
        else                     self.menuHud0 set_text("^5  Intro Screen");
        if (self.menuIndex == 1) self.menuHud1 set_text("   MP Afghan");
        else                     self.menuHud1 set_text("^7  MP Afghan");
        if (self.menuIndex == 2) self.menuHud2 set_text("   MP Nuke");
        else                     self.menuHud2 set_text("^5  MP Nuke");
        if (self.menuIndex == 3) self.menuHud3 set_text("   MP Nuke Aftermath");
        else                     self.menuHud3 set_text("^7  MP Nuke Aftermath");
        if (self.menuIndex == 4) self.menuHud4 set_text("   MP Outro");
        else                     self.menuHud4 set_text("^5  MP Outro");
        if (self.menuIndex == 5) self.menuHud5 set_text("   Near Death");
        else                     self.menuHud5 set_text("^7  Near Death");
        if (self.menuIndex == 6) self.menuHud6 set_text("   Near Death MP");
        else                     self.menuHud6 set_text("^5  Near Death MP");
        if (self.menuIndex == 7) self.menuHud7 set_text("   Thermal MP");
        else                     self.menuHud7 set_text("^7  Thermal MP");
        if (self.menuIndex == 8) self.menuHud8 set_text("   Page 1 <-");
        else                     self.menuHud8 set_text("^5  Page 1 ^7<-");
        return;
    }
    if (self.menuPage == "giveweapons")
    {
        if (self.menuIndex == 0)
            self.menuHud0 set_text("   Sniper Rifles >>");
        else
            self.menuHud0 set_text("^5  Sniper Rifles >>");
        if (self.menuIndex == 1)
            self.menuHud1 set_text("   Handguns >>");
        else
            self.menuHud1 set_text("^7  Handguns >>");
        if (self.menuIndex == 2)
            self.menuHud2 set_text("   Shotguns >>");
        else
            self.menuHud2 set_text("^5  Shotguns >>");
        if (self.menuIndex == 3)
            self.menuHud3 set_text("   Machine Pistols >>");
        else
            self.menuHud3 set_text("^7  Machine Pistols >>");
        if (self.menuIndex == 4)
            self.menuHud4 set_text("   Assault Rifles >>");
        else
            self.menuHud4 set_text("^5  Assault Rifles >>");
        if (self.menuIndex == 5)
            self.menuHud5 set_text("   Submachine Guns >>");
        else
            self.menuHud5 set_text("^7  Submachine Guns >>");
        if (self.menuIndex == 6)
            self.menuHud6 set_text("   Light Machine Guns >>");
        else
            self.menuHud6 set_text("^5  Light Machine Guns >>");
        if (self.menuIndex == 7)
            self.menuHud7 set_text("   Specials >>");
        else
            self.menuHud7 set_text("^7  Specials >>");
        if (self.menuIndex == 8)
            self.menuHud8 set_text("   Lethals >>");
        else
            self.menuHud8 set_text("^5  Lethals >>");
        if (self.menuIndex == 9)
            self.menuHud9 set_text("   Tacticals >>");
        else
            self.menuHud9 set_text("^7  Tacticals >>");
        return;
    }
    if (self.menuPage == "snipers")
    {
        if (self.menuIndex == 0)
            self.menuHud0 set_text("   Give Intervention");
        else
            self.menuHud0 set_text("^5  Give Intervention");
        if (self.menuIndex == 1)
            self.menuHud1 set_text("   Give Barrett .50cal");
        else
            self.menuHud1 set_text("^7  Give Barrett .50cal");
        if (self.menuIndex == 2)
            self.menuHud2 set_text("   Give WA2000");
        else
            self.menuHud2 set_text("^5  Give WA2000");
        if (self.menuIndex == 3)
            self.menuHud3 set_text("   Give M21 EBR");
        else
            self.menuHud3 set_text("^7  Give M21 EBR");
        if (self.menuIndex == 4)
            self.menuHud4 set_text("   Give M40A3");
        else
            self.menuHud4 set_text("^5  Give M40A3");
        if (self.menuIndex == 5)
            self.menuHud5 set_text("   Give Dragunov");
        else
            self.menuHud5 set_text("^7  Give Dragunov");
        return;
    }
    if (self.menuPage == "handguns")
    {
        if (self.menuIndex == 0)
            self.menuHud0 set_text("   Give USP .45");
        else
            self.menuHud0 set_text("^5  Give USP .45");
        if (self.menuIndex == 1)
            self.menuHud1 set_text("   Give Magnum");
        else
            self.menuHud1 set_text("^7  Give Magnum");
        if (self.menuIndex == 2)
            self.menuHud2 set_text("   Give M9");
        else
            self.menuHud2 set_text("^5  Give M9");
        if (self.menuIndex == 3)
            self.menuHud3 set_text("   Give Desert Eagle");
        else
            self.menuHud3 set_text("^7  Give Desert Eagle");
        if (self.menuIndex == 4)
            self.menuHud4 set_text("   Give Gold Desert Eagle");
        else
            self.menuHud4 set_text("^5  Give Gold Desert Eagle");
        return;
    }
    if (self.menuPage == "shotguns")
    {
        if (self.menuIndex == 0)
            self.menuHud0 set_text("   Give SPAS-12");
        else
            self.menuHud0 set_text("^5  Give SPAS-12");
        if (self.menuIndex == 1)
            self.menuHud1 set_text("   Give AA-12");
        else
            self.menuHud1 set_text("^7  Give AA-12");
        if (self.menuIndex == 2)
            self.menuHud2 set_text("   Give Striker");
        else
            self.menuHud2 set_text("^5  Give Striker");
        if (self.menuIndex == 3)
            self.menuHud3 set_text("   Give Ranger");
        else
            self.menuHud3 set_text("^7  Give Ranger");
        if (self.menuIndex == 4)
            self.menuHud4 set_text("   Give M1014");
        else
            self.menuHud4 set_text("^5  Give M1014");
        if (self.menuIndex == 5)
            self.menuHud5 set_text("   Give Model 1887");
        else
            self.menuHud5 set_text("^7  Give Model 1887");
        return;
    }
    if (self.menuPage == "machinepistols")
    {
        if (self.menuIndex == 0)
            self.menuHud0 set_text("   Give PP2000");
        else
            self.menuHud0 set_text("^5  Give PP2000");
        if (self.menuIndex == 1)
            self.menuHud1 set_text("   Give G18");
        else
            self.menuHud1 set_text("^7  Give G18");
        if (self.menuIndex == 2)
            self.menuHud2 set_text("   Give M93 Raffica");
        else
            self.menuHud2 set_text("^5  Give M93 Raffica");
        if (self.menuIndex == 3)
            self.menuHud3 set_text("   Give TMP");
        else
            self.menuHud3 set_text("^7  Give TMP");
        return;
    }
    if (self.menuPage == "assaultrifles")
    {
        if (self.menuIndex == 0)
            self.menuHud0 set_text("   Give M4A1");
        else
            self.menuHud0 set_text("^5  Give M4A1");
        if (self.menuIndex == 1)
            self.menuHud1 set_text("   Give FAMAS");
        else
            self.menuHud1 set_text("^7  Give FAMAS");
        if (self.menuIndex == 2)
            self.menuHud2 set_text("   Give SCAR-H");
        else
            self.menuHud2 set_text("^5  Give SCAR-H");
        if (self.menuIndex == 3)
            self.menuHud3 set_text("   Give TAR-21");
        else
            self.menuHud3 set_text("^7  Give TAR-21");
        if (self.menuIndex == 4)
            self.menuHud4 set_text("   Give FAL");
        else
            self.menuHud4 set_text("^5  Give FAL");
        if (self.menuIndex == 5)
            self.menuHud5 set_text("   Give M16A4");
        else
            self.menuHud5 set_text("^7  Give M16A4");
        if (self.menuIndex == 6)
            self.menuHud6 set_text("   Give ACR");
        else
            self.menuHud6 set_text("^5  Give ACR");
        if (self.menuIndex == 7)
            self.menuHud7 set_text("   Give F2000");
        else
            self.menuHud7 set_text("^7  Give F2000");
        if (self.menuIndex == 8)
            self.menuHud8 set_text("   Give AK-47");
        else
            self.menuHud8 set_text("^5  Give AK-47");
        if (self.menuIndex == 9)
            self.menuHud9 set_text("   Give AK-47 Classic");
        else
            self.menuHud9 set_text("^7  Give AK-47 Classic");
        return;
    }
    if (self.menuPage == "smgs")
    {
        if (self.menuIndex == 0)
            self.menuHud0 set_text("   Give MP5K");
        else
            self.menuHud0 set_text("^5  Give MP5K");
        if (self.menuIndex == 1)
            self.menuHud1 set_text("   Give UMP45");
        else
            self.menuHud1 set_text("^7  Give UMP45");
        if (self.menuIndex == 2)
            self.menuHud2 set_text("   Give Vector");
        else
            self.menuHud2 set_text("^5  Give Vector");
        if (self.menuIndex == 3)
            self.menuHud3 set_text("   Give P90");
        else
            self.menuHud3 set_text("^7  Give P90");
        if (self.menuIndex == 4)
            self.menuHud4 set_text("   Give Mini-Uzi");
        else
            self.menuHud4 set_text("^5  Give Mini-Uzi");
        if (self.menuIndex == 5)
            self.menuHud5 set_text("   Give AK-74u");
        else
            self.menuHud5 set_text("^7  Give AK-74u");
        if (self.menuIndex == 6)
            self.menuHud6 set_text("   Give Peacekeeper");
        else
            self.menuHud6 set_text("^5  Give Peacekeeper");
        return;
    }
    if (self.menuPage == "lmgs")
    {
        if (self.menuIndex == 0)
            self.menuHud0 set_text("   Give L86 LSW");
        else
            self.menuHud0 set_text("^5  Give L86 LSW");
        if (self.menuIndex == 1)
            self.menuHud1 set_text("   Give RPD");
        else
            self.menuHud1 set_text("^7  Give RPD");
        if (self.menuIndex == 2)
            self.menuHud2 set_text("   Give MG4");
        else
            self.menuHud2 set_text("^5  Give MG4");
        if (self.menuIndex == 3)
            self.menuHud3 set_text("   Give AUG HBAR");
        else
            self.menuHud3 set_text("^7  Give AUG HBAR");
        if (self.menuIndex == 4)
            self.menuHud4 set_text("   Give M240");
        else
            self.menuHud4 set_text("^5  Give M240");
        return;
    }
    if (self.menuPage == "attachments")
    {
        if (!isDefined(self.attachCount) || self.attachCount == 0)
        {
            self.menuHud0 set_text("^1No attachments for this weapon");
            return;
        }
        if (isDefined(self.attach0))
        {
            if (self.menuIndex == 0) self.menuHud0 set_text("   " + self.attach0);
            else self.menuHud0 set_text("^5  " + self.attach0);
        }
        if (isDefined(self.attach1))
        {
            if (self.menuIndex == 1) self.menuHud1 set_text("   " + self.attach1);
            else self.menuHud1 set_text("^7  " + self.attach1);
        }
        if (isDefined(self.attach2))
        {
            if (self.menuIndex == 2) self.menuHud2 set_text("   " + self.attach2);
            else self.menuHud2 set_text("^5  " + self.attach2);
        }
        if (isDefined(self.attach3))
        {
            if (self.menuIndex == 3) self.menuHud3 set_text("   " + self.attach3);
            else self.menuHud3 set_text("^7  " + self.attach3);
        }
        if (isDefined(self.attach4))
        {
            if (self.menuIndex == 4) self.menuHud4 set_text("   " + self.attach4);
            else self.menuHud4 set_text("^5  " + self.attach4);
        }
        if (isDefined(self.attach5))
        {
            if (self.menuIndex == 5) self.menuHud5 set_text("   " + self.attach5);
            else self.menuHud5 set_text("^7  " + self.attach5);
        }
        if (isDefined(self.attach6))
        {
            if (self.menuIndex == 6) self.menuHud6 set_text("   " + self.attach6);
            else self.menuHud6 set_text("^5  " + self.attach6);
        }
        if (isDefined(self.attach7))
        {
            if (self.menuIndex == 7) self.menuHud7 set_text("   " + self.attach7);
            else self.menuHud7 set_text("^7  " + self.attach7);
        }
        if (isDefined(self.attach8))
        {
            if (self.menuIndex == 8) self.menuHud8 set_text("   " + self.attach8);
            else self.menuHud8 set_text("^5  " + self.attach8);
        }
        if (isDefined(self.attach9))
        {
            if (self.menuIndex == 9) self.menuHud9 set_text("   " + self.attach9);
            else self.menuHud9 set_text("^7  " + self.attach9);
        }
        return;
    }
    if (self.menuPage == "specials")
    {
        if (self.menuIndex == 0)
            self.menuHud0 set_text("   Give Riot Shield");
        else
            self.menuHud0 set_text("^5  Give Riot Shield");
        if (self.menuIndex == 1)
            self.menuHud1 set_text("   Launchers >>");
        else
            self.menuHud1 set_text("^7  Launchers >>");
        return;
    }
    if (self.menuPage == "launchers")
    {
        if (self.menuIndex == 0)
            self.menuHud0 set_text("   Give AT4-HS");
        else
            self.menuHud0 set_text("^5  Give AT4-HS");
        if (self.menuIndex == 1)
            self.menuHud1 set_text("   Give Thumper");
        else
            self.menuHud1 set_text("^7  Give Thumper");
        if (self.menuIndex == 2)
            self.menuHud2 set_text("   Give Stinger");
        else
            self.menuHud2 set_text("^5  Give Stinger");
        if (self.menuIndex == 3)
            self.menuHud3 set_text("   Give Javelin");
        else
            self.menuHud3 set_text("^7  Give Javelin");
        if (self.menuIndex == 4)
            self.menuHud4 set_text("   Give RPG-7");
        else
            self.menuHud4 set_text("^5  Give RPG-7");
        return;
    }
    if (self.menuPage == "lethals")
    {
        if (self.menuIndex == 0)
            self.menuHud0 set_text("   Give Frag Grenade");
        else
            self.menuHud0 set_text("^5  Give Frag Grenade");
        if (self.menuIndex == 1)
            self.menuHud1 set_text("   Give Semtex");
        else
            self.menuHud1 set_text("^7  Give Semtex");
        if (self.menuIndex == 2)
            self.menuHud2 set_text("   Give Throwing Knife");
        else
            self.menuHud2 set_text("^5  Give Throwing Knife");
        if (self.menuIndex == 3)
            self.menuHud3 set_text("   Give Claymore");
        else
            self.menuHud3 set_text("^7  Give Claymore");
        if (self.menuIndex == 4)
            self.menuHud4 set_text("   Give C4");
        else
            self.menuHud4 set_text("^5  Give C4");
        return;
    }
    if (self.menuPage == "tacticals")
    {
        if (self.menuIndex == 0)
            self.menuHud0 set_text("   Give Flash Grenade");
        else
            self.menuHud0 set_text("^5  Give Flash Grenade");
        if (self.menuIndex == 1)
            self.menuHud1 set_text("   Give Stun Grenade");
        else
            self.menuHud1 set_text("^7  Give Stun Grenade");
        if (self.menuIndex == 2)
            self.menuHud2 set_text("   Give Smoke Grenade");
        else
            self.menuHud2 set_text("^5  Give Smoke Grenade");
        return;
    }
    if (self.menuPage == "mainmods")
    {
        if (self.menuIndex == 0)
            self.menuHud0 set_text("   Trickshot Mods >>");
        else
            self.menuHud0 set_text("^5  Trickshot Mods >>");
        if (self.menuIndex == 1)
            self.menuHud1 set_text("   Save Position");
        else
            self.menuHud1 set_text("^7  Save Position");
        if (self.menuIndex == 2)
            self.menuHud2 set_text("   Load Position");
        else
            self.menuHud2 set_text("^5  Load Position");
        if (self.menuIndex == 3)
            self.menuHud3 set_text("   Give Ammo");
        else
            self.menuHud3 set_text("^7  Give Ammo");
        if (self.menuIndex == 4)
            self.menuHud4 set_text("   Force UAV [" + forceUavPlain + "]");
        else
            self.menuHud4 set_text("^5  Force UAV ^7[" + forceUavStatus + "^7]");
        if (self.menuIndex == 5)
            self.menuHud5 set_text("   Killcams [" + killcamPlain + "]");
        else
            self.menuHud5 set_text("^7  Killcams ^7[" + killcamStatus + "^7]");
        if (self.menuIndex == 6)
            self.menuHud6 set_text("   God Mode [" + godPlain + "]");
        else
            self.menuHud6 set_text("^5  God Mode ^7[" + godStatus + "^7]");
        if (self.menuIndex == 7)
            self.menuHud7 set_text("   UFO Mode [" + ufoPlain + "]");
        else
            self.menuHud7 set_text("^7  UFO Mode ^7[" + ufoStatus + "^7]");
        return;
    }
    if (self.menuPage == "bots")
    {
        if (self.menuIndex == 0)
            self.menuHud0 set_text("   Add Bots >>");
        else
            self.menuHud0 set_text("^5  Add Bots >>");
        if (self.menuIndex == 1)
            self.menuHud1 set_text("   Freeze/Unfreeze Bots");
        else
            self.menuHud1 set_text("^7  Freeze/Unfreeze Bots");
        if (self.menuIndex == 2)
            self.menuHud2 set_text("   Teleport Bots To Me");
        else
            self.menuHud2 set_text("^5  Teleport Bots To Me");
        if (self.menuIndex == 3)
            self.menuHud3 set_text("   Teleport Bots To Crosshair");
        else
            self.menuHud3 set_text("^7  Teleport Bots To Crosshair");
        if (self.menuIndex == 4)
            self.menuHud4 set_text("   Teams and Difficulty >>");
        else
            self.menuHud4 set_text("^5  Teams and Difficulty >>");
        if (self.menuIndex == 5)
            self.menuHud5 set_text("   Bot Combat [" + botCombatPlain + "]");
        else
            self.menuHud5 set_text("^7  Bot Combat ^7[" + botCombatStatus + "^7]");
        if (self.menuIndex == 6)
            self.menuHud6 set_text("   Scatter Bots");
        else
            self.menuHud6 set_text("^5  Scatter Bots");
        if (self.menuIndex == 7)
            self.menuHud7 set_text("   Bot Chat [" + chatPlain + "]");
        else
            self.menuHud7 set_text("^7  Bot Chat ^7[" + chatStatus + "^7]");
        if (self.menuIndex == 8)
            self.menuHud8 set_text("   Kill All Bots");
        else
            self.menuHud8 set_text("^5  Kill All Bots");
        if (self.menuIndex == 9)
            self.menuHud9 set_text("   Kick All Bots");
        else
            self.menuHud9 set_text("^7  Kick All Bots");
        return;
    }
    if (self.menuPage == "teamsdifficulty")
    {
        if (self.menuIndex == 0)
            self.menuHud0 set_text("   Bot Team [" + botTeamPlain + "]");
        else
            self.menuHud0 set_text("^5  Bot Team ^7[" + botTeamStatus + "^7]");
        if (self.menuIndex == 1)
            self.menuHud1 set_text("   Axis Bot Count [+] [" + axisBotCountPlain + "]");
        else
            self.menuHud1 set_text("^7  Axis Bot Count [+] ^7[^5" + getDvarInt("bots_team_amount") + "^7]");
        if (self.menuIndex == 2)
            self.menuHud2 set_text("   Axis Bot Count [-] [" + axisBotCountPlain + "]");
        else
            self.menuHud2 set_text("^5  Axis Bot Count [-] ^7[^5" + getDvarInt("bots_team_amount") + "^7]");
        if (self.menuIndex == 3)
            self.menuHud3 set_text("   Force Bot Team [" + forceBotTeamPlain + "]");
        else
            self.menuHud3 set_text("^7  Force Bot Team ^7[" + forceBotTeamStatus + "^7]");
        if (self.menuIndex == 4)
            self.menuHud4 set_text("   Bot Team Target [" + botTeamTargetPlain + "]");
        else
            self.menuHud4 set_text("^5  Bot Team Target ^7[" + botTeamTargetStatus + "^7]");
        if (self.menuIndex == 5)
            self.menuHud5 set_text("   Difficulty [" + difficultyPlain + "]");
        else
            self.menuHud5 set_text("^7  Difficulty ^7[" + difficultyStatus + "^7]");
        return;
    }
    if (self.menuPage == "addbots")
    {
        if (self.menuIndex == 0)
            self.menuHud0 set_text("   Add 1 Bot");
        else
            self.menuHud0 set_text("^5  Add 1 Bot");
        if (self.menuIndex == 1)
            self.menuHud1 set_text("   Add 3 Bots");
        else
            self.menuHud1 set_text("^7  Add 3 Bots");
        if (self.menuIndex == 2)
            self.menuHud2 set_text("   Add 7 Bots");
        else
            self.menuHud2 set_text("^5  Add 7 Bots");
        if (self.menuIndex == 3)
            self.menuHud3 set_text("   Add 11 Bots");
        else
            self.menuHud3 set_text("^7  Add 11 Bots");
        if (self.menuIndex == 4)
            self.menuHud4 set_text("   Add 17 Bots");
        else
            self.menuHud4 set_text("^5  Add 17 Bots");
        return;
    }
    if (self.menuPage == "lobby")
    {
        if (self.menuIndex == 0)
            self.menuHud0 set_text("   Set Time >>");
        else
            self.menuHud0 set_text("^5  Set Time >>");
        if (self.menuIndex == 1)
            self.menuHud1 set_text("   Lobby Health [" + healthPlain + "]");
        else
            self.menuHud1 set_text("^7  Lobby Health ^7[" + healthStatus + "^7]");
        if (self.menuIndex == 2)
            self.menuHud2 set_text("   Trickshot Damage Only [" + trickshotDamageOnlyPlain + "]");
        else
            self.menuHud2 set_text("^5  Trickshot Damage Only ^7[" + trickshotDamageOnlyStatus + "^7]");
        if (self.menuIndex == 3)
            self.menuHud3 set_text("   Set Gamemode >>");
        else
            self.menuHud3 set_text("^7  Set Gamemode >>");
        if (self.menuIndex == 4)
            self.menuHud4 set_text("   Set Score >>");
        else
            self.menuHud4 set_text("^5  Set Score >>");
        if (self.menuIndex == 5)
            self.menuHud5 set_text("   TDM Options >>");
        else
            self.menuHud5 set_text("^7  TDM Options >>");
        if (self.menuIndex == 6)
            self.menuHud6 set_text("   Restart Game");
        else
            self.menuHud6 set_text("^5  Restart Game");
        if (self.menuIndex == 7)
            self.menuHud7 set_text("   Instant End Game");
        else
            self.menuHud7 set_text("^7  Instant End Game");
        return;
    }
    if (self.menuPage == "setgamemode")
    {
        if (self.menuIndex == 0)
            self.menuHud0 set_text("   Change to FFA");
        else
            self.menuHud0 set_text("^5  Change to FFA");
        if (self.menuIndex == 1)
            self.menuHud1 set_text("   Change to TDM");
        else
            self.menuHud1 set_text("^7  Change to TDM");
        if (self.menuIndex == 2)
            self.menuHud2 set_text("   Change to SND");
        else
            self.menuHud2 set_text("^5  Change to SND");
        return;
    }
    if (self.menuPage == "tdmoptions")
    {
        if (self.menuIndex == 0)
            self.menuHud0 set_text("   Friendly Fire [" + friendlyFirePlain + "]");
        else
            self.menuHud0 set_text("^5  Friendly Fire ^7[" + friendlyFireStatus + "^7]");
        if (self.menuIndex == 1)
            self.menuHud1 set_text("   Friendly Team Last");
        else
            self.menuHud1 set_text("^7  Friendly Team Last");
        if (self.menuIndex == 2)
            self.menuHud2 set_text("   Enemy Team Last");
        else
            self.menuHud2 set_text("^5  Enemy Team Last");
        if (self.menuIndex == 3)
            self.menuHud3 set_text("   Reset Friendly Score");
        else
            self.menuHud3 set_text("^7  Reset Friendly Score");
        if (self.menuIndex == 4)
            self.menuHud4 set_text("   Reset Enemy Score");
        else
            self.menuHud4 set_text("^5  Reset Enemy Score");
        return;
    }
    if (self.menuPage == "settime")
    {
        if (self.menuIndex == 0)
            self.menuHud0 set_text("   Unlimited Time");
        else
            self.menuHud0 set_text("^5  Unlimited Time");
        if (self.menuIndex == 1)
            self.menuHud1 set_text("   Add 1 Minute");
        else
            self.menuHud1 set_text("^7  Add 1 Minute");
        if (self.menuIndex == 2)
            self.menuHud2 set_text("   Add 5 Minutes");
        else
            self.menuHud2 set_text("^5  Add 5 Minutes");
        if (self.menuIndex == 3)
            self.menuHud3 set_text("   Add 10 Minutes");
        else
            self.menuHud3 set_text("^7  Add 10 Minutes");
        return;
    }
    if (self.menuPage == "setscore")
    {
        if (self.menuIndex == 0)
            self.menuHud0 set_text("   Set FFA Score >>");
        else
            self.menuHud0 set_text("^5  Set FFA Score >>");
        if (self.menuIndex == 1)
            self.menuHud1 set_text("   Set TDM Score >>");
        else
            self.menuHud1 set_text("^7  Set TDM Score >>");
        return;
    }
    if (self.menuPage == "ffascore")
    {
        if (self.menuIndex == 0)
            self.menuHud0 set_text("   Set Score Unlimited");
        else
            self.menuHud0 set_text("^5  Set Score Unlimited");
        if (self.menuIndex == 1)
            self.menuHud1 set_text("   Set Score 1000");
        else
            self.menuHud1 set_text("^7  Set Score 1000");
        if (self.menuIndex == 2)
            self.menuHud2 set_text("   Set Score 1500");
        else
            self.menuHud2 set_text("^5  Set Score 1500");
        if (self.menuIndex == 3)
            self.menuHud3 set_text("   Set Score 3000");
        else
            self.menuHud3 set_text("^7  Set Score 3000");
        return;
    }
    if (self.menuPage == "tdmscore")
    {
        if (self.menuIndex == 0)
            self.menuHud0 set_text("   Set Score Unlimited");
        else
            self.menuHud0 set_text("^5  Set Score Unlimited");
        if (self.menuIndex == 1)
            self.menuHud1 set_text("   Set Score 2500");
        else
            self.menuHud1 set_text("^7  Set Score 2500");
        if (self.menuIndex == 2)
            self.menuHud2 set_text("   Set Score 5000");
        else
            self.menuHud2 set_text("^5  Set Score 5000");
        if (self.menuIndex == 3)
            self.menuHud3 set_text("   Set Score 7500");
        else
            self.menuHud3 set_text("^7  Set Score 7500");
        return;
    }
}
closeMenuHud()
{
    self.menuOpen = false;
    self.menuPage = "main";
    self destroyMenuHud();
}
destroyMenuHud()
{
    self notify("rainy_menu_closed");
    if (isDefined(self.menuHudBackdrop))
        self.menuHudBackdrop destroy();
    if (isDefined(self.menuHudStripe))
        self.menuHudStripe destroy();
    if (isDefined(self.menuHudUnderline))
        self.menuHudUnderline destroy();
    if (isDefined(self.menuHudSelectBar))
        self.menuHudSelectBar destroy();
    if (isDefined(self.menuHudGrain))
        self.menuHudGrain destroy();
    if (isDefined(self.menuHudFillTop))
        self.menuHudFillTop destroy();
    if (isDefined(self.menuHudFillMid))
        self.menuHudFillMid destroy();
    if (isDefined(self.menuHudFillBottom))
        self.menuHudFillBottom destroy();
    if (isDefined(self.menuHudInnerGlow))
        self.menuHudInnerGlow destroy();
    if (isDefined(self.menuHudLeftRailShadow))
        self.menuHudLeftRailShadow destroy();
    if (isDefined(self.menuHudLeftRail))
        self.menuHudLeftRail destroy();
    if (isDefined(self.menuHudRightRailShadow))
        self.menuHudRightRailShadow destroy();
    if (isDefined(self.menuHudRightRail))
        self.menuHudRightRail destroy();
    if (isDefined(self.menuHudHeaderLine))
        self.menuHudHeaderLine destroy();
    if (isDefined(self.menuHudTopLine))
        self.menuHudTopLine destroy();
    if (isDefined(self.menuHudTopLineGlow))
        self.menuHudTopLineGlow destroy();
    if (isDefined(self.menuHudBottomLine))
        self.menuHudBottomLine destroy();
    if (isDefined(self.menuHudSelectTick))
        self.menuHudSelectTick destroy();
    if (isDefined(self.menuHudScanLine))
        self.menuHudScanLine destroy();
    if (isDefined(self.menuHudTitleGlow))
        self.menuHudTitleGlow destroy();
    if (isDefined(self.menuHudStatus))
        self.menuHudStatus destroy();
    if (isDefined(self.menuHudPageLabel))
        self.menuHudPageLabel destroy();
    if (isDefined(self.menuHudFooter))
        self.menuHudFooter destroy();
    if (isDefined(self.menuHudTitle))
        self.menuHudTitle destroy();
    if (isDefined(self.menuHud0))
        self.menuHud0 destroy();
    if (isDefined(self.menuHud1))
        self.menuHud1 destroy();
    if (isDefined(self.menuHud2))
        self.menuHud2 destroy();
    if (isDefined(self.menuHud3))
        self.menuHud3 destroy();
    if (isDefined(self.menuHud4))
        self.menuHud4 destroy();
    if (isDefined(self.menuHud5))
        self.menuHud5 destroy();
    if (isDefined(self.menuHud6))
        self.menuHud6 destroy();
    if (isDefined(self.menuHud7))
        self.menuHud7 destroy();
    if (isDefined(self.menuHud8))
        self.menuHud8 destroy();
    if (isDefined(self.menuHud9))
        self.menuHud9 destroy();
    self.menuHudBackdrop = undefined;
    self.menuHudGrain = undefined;
    self.menuHudFillTop = undefined;
    self.menuHudFillMid = undefined;
    self.menuHudFillBottom = undefined;
    self.menuHudInnerGlow = undefined;
    self.menuHudStripe = undefined;
    self.menuHudUnderline = undefined;
    self.menuHudLeftRailShadow = undefined;
    self.menuHudLeftRail = undefined;
    self.menuHudRightRailShadow = undefined;
    self.menuHudRightRail = undefined;
    self.menuHudHeaderLine = undefined;
    self.menuHudTopLine = undefined;
    self.menuHudTopLineGlow = undefined;
    self.menuHudBottomLine = undefined;
    self.menuHudSelectBar = undefined;
    self.menuHudSelectTick = undefined;
    self.menuHudScanLine = undefined;
    self.menuHudTitleGlow = undefined;
    self.menuHudTitle = undefined;
    self.menuHudStatus = undefined;
    self.menuHudPageLabel = undefined;
    self.menuHudFooter = undefined;
    self.menuHud0 = undefined;
    self.menuHud1 = undefined;
    self.menuHud2 = undefined;
    self.menuHud3 = undefined;
    self.menuHud4 = undefined;
    self.menuHud5 = undefined;
    self.menuHud6 = undefined;
    self.menuHud7 = undefined;
    self.menuHud8 = undefined;
    self.menuHud9 = undefined;
}
menuSelect()
{
    if (!isDefined(self.menuPage))
        self.menuPage = "main";
    if (self.menuPage == "main")
    {
        if (self.menuIndex == 0)
        {
            self.menuPage = "mainmods";
            self.menuIndex = 0;
            self updateMenuHud();
            return;
        }
        else if (self.menuIndex == 1)
        {
            self.menuPage = "lobby";
            self.menuIndex = 0;
            self updateMenuHud();
            return;
        }
        else if (self.menuIndex == 2)
        {
            self.menuPage = "bots";
            self.menuIndex = 0;
            self updateMenuHud();
            return;
        }
        else if (self.menuIndex == 3)
        {
            self.menuPage = "weapons";
            self.menuIndex = 0;
            self updateMenuHud();
            return;
        }
        else if (self.menuIndex == 4)
        {
            self.menuPage = "fun";
            self.menuIndex = 0;
            self updateMenuHud();
            return;
        }
        else if (self.menuIndex == 5)
        {
            self.menuPage = "aimbot";
            self.menuIndex = 0;
            self updateMenuHud();
            return;
        }
        else if (self.menuIndex == 6)
        {
            self rainyOpenClientsMenu();
            return;
        }
    }
    else if (self.menuPage == "fun")
    {
        if (self.menuIndex == 0)
        {
            self.menuPage = "visions";
            self.menuIndex = 0;
            self updateMenuHud();
            return;
        }
        else if (self.menuIndex == 1)
        {
            if (getDvarInt("camera_thirdPerson") == 1)
            {
                setDvar("camera_thirdPerson", "0");
                self thread rainyShowRaisedMessage("^7Third Person ^7[^5OFF^7]");
            }
            else
            {
                setDvar("camera_thirdPerson", "1");
                self thread rainyShowRaisedMessage("^7Third Person ^7[^5ON^7]");
            }
        }
        else if (self.menuIndex == 2)
        {
            self cyclePlayerSpeed();
        }
        else if (self.menuIndex == 3)
        {
            self cycleJump();
        }
        else if (self.menuIndex == 4)
        {
            self cyclePlayerFOV();
        }
    }
    else if (self.menuPage == "trickshotmods")
    {
        if (self.menuIndex == 0)
        {
            self toggleAutoRefillAmmo();
        }
        else if (self.menuIndex == 1)
        {
            self fastLastFFA();
        }
        else if (self.menuIndex == 2)
        {
            self fastLastTDM();
        }
        else if (self.menuIndex == 3)
        {
            self resetScoreFFA();
        }
        else if (self.menuIndex == 4)
        {
            self.menuPage = "spawnables";
            self.menuIndex = 0;
            self updateMenuHud();
            return;
        }
        else if (self.menuIndex == 5)
        {
            self toggleInfiniteCarePackage();
        }
        else if (self.menuIndex == 6)
        {
            self toggleForgeMode();
        }
        else if (self.menuIndex == 7)
        {
            self toggleNoPlayerCollision();
        }
        else if (self.menuIndex == 8)
        {
            self thread toggleCanswapBind();
        }
        else if (self.menuIndex == 9)
        {
            self.menuPage = "trickshotmods2";
            self.menuIndex = 0;
            self updateMenuHud();
            return;
        }
    }
    else if (self.menuPage == "trickshotmods2")
    {
        if (self.menuIndex == 0)
        {
            self toggleTsPlatformBind();
        }
        else if (self.menuIndex == 1)
        {
            self toggleTrickshotDistance();
        }
        else if (self.menuIndex == 2)
        {
            self toggleAlmostHits();
        }
        else if (self.menuIndex == 3)
        {
            self.menuPage = "trickshotmods";
            self.menuIndex = 9;
            self updateMenuHud();
            return;
        }
    }
    else if (self.menuPage == "spawnables")
    {
        if (self.menuIndex == 0)
        {
            self thread spawnPlatformGrid();
        }
        else if (self.menuIndex == 1)
        {
            self thread spawnTrickshotPlatformAtCrosshair();
        }
        else if (self.menuIndex == 2)
        {
            self thread spawnPlatformBelow();
        }
        else if (self.menuIndex == 3)
        {
            self thread spawnPlatformAtCrosshair();
        }
        else if (self.menuIndex == 4)
        {
            self thread removeAllPlatforms();
        }
    }
    if (self.menuPage == "aimbot")
    {
        if (self.menuIndex == 0)
        {
            self toggleTsAimbot();
        }
        else if (self.menuIndex == 1)
        {
            self toggleWallbang();
        }
        else if (self.menuIndex == 2)
        {
            self toggleWallbangSnap();
        }
        else if (self.menuIndex == 3)
        {
            self toggleSilentAim();
        }
        else if (self.menuIndex == 4)
        {
            self toggleSnapAim();
        }
        else if (self.menuIndex == 5)
        {
            self toggleUnfairAimbot();
        }
    }
    if (self.menuPage == "weapons")
    {
        if (self.menuIndex == 0)
        {
            self.menuPage = "giveweapons";
            self.menuIndex = 0;
            self updateMenuHud();
            return;
        }
        else if (self.menuIndex == 1)
        {
            self loadAttachmentsForWeapon();
            self.menuPage = "attachments";
            self.menuIndex = 0;
            self updateMenuHud();
            return;
        }
        else if (self.menuIndex == 2)
        {
            self.menuPage = "killstreaks";
            self.menuIndex = 0;
            self updateMenuHud();
            return;
        }
        else if (self.menuIndex == 3)
        {
            self.menuPage = "perkhub";
            self.menuIndex = 0;
            self updateMenuHud();
            return;
        }
        else if (self.menuIndex == 4)
        {
            if (!self getWeaponCanHaveCamo(self getCurrentWeapon()))
            {
                self thread rainyShowRaisedMessage("^5This weapon can't have a camo");
                return;
            }
            self loadCamoList();
            self.menuPage = "givecamo";
            self.menuIndex = 0;
            self updateMenuHud();
            return;
        }
        else if (self.menuIndex == 5)
        {
            self deleteCurrentMenuWeapon();
        }
        else if (self.menuIndex == 6)
        {
            self takeGroundWeapon();
        }
        else if (self.menuIndex == 7)
        {
            self dropCurrentMenuWeapon();
        }
    }
    else if (self.menuPage == "givecamo")
    {
        camoIdx = undefined;
        if (self.menuIndex == 0) camoIdx = self.camoIdx0;
        else if (self.menuIndex == 1) camoIdx = self.camoIdx1;
        else if (self.menuIndex == 2) camoIdx = self.camoIdx2;
        else if (self.menuIndex == 3) camoIdx = self.camoIdx3;
        else if (self.menuIndex == 4) camoIdx = self.camoIdx4;
        else if (self.menuIndex == 5) camoIdx = self.camoIdx5;
        else if (self.menuIndex == 6) camoIdx = self.camoIdx6;
        else if (self.menuIndex == 7) camoIdx = self.camoIdx7;
        else if (self.menuIndex == 8) camoIdx = self.camoIdx8;
        else if (self.menuIndex == 9) camoIdx = self.camoIdx9;
        if (isDefined(camoIdx))
            self thread giveCamoToWeapon(camoIdx);
    }
    else if (self.menuPage == "killstreaks")
    {
        if (self.menuIndex == 0) self rainyRemoveTopKillstreak();
        else if (self.menuIndex == 1) self maps\mp\killstreaks\_killstreaks::tryGiveKillstreak("uav",                  3);
        else if (self.menuIndex == 2) self maps\mp\killstreaks\_killstreaks::tryGiveKillstreak("airdrop",             4);
        else if (self.menuIndex == 3) self maps\mp\killstreaks\_killstreaks::tryGiveKillstreak("counter_uav",         4);
        else if (self.menuIndex == 4) self maps\mp\killstreaks\_killstreaks::tryGiveKillstreak("sentry",              5);
        else if (self.menuIndex == 5) self maps\mp\killstreaks\_killstreaks::tryGiveKillstreak("predator_missile",    5);
        else if (self.menuIndex == 6) self maps\mp\killstreaks\_killstreaks::tryGiveKillstreak("precision_airstrike", 6);
        else if (self.menuIndex == 7) self maps\mp\killstreaks\_killstreaks::tryGiveKillstreak("harrier_airstrike",   7);
        else if (self.menuIndex == 8) self maps\mp\killstreaks\_killstreaks::tryGiveKillstreak("helicopter",          7);
        else if (self.menuIndex == 9)
        {
            self.menuPage = "killstreaks2";
            self.menuIndex = 0;
            self updateMenuHud();
            return;
        }
    }
    else if (self.menuPage == "killstreaks2")
    {
        if (self.menuIndex == 0)      self maps\mp\killstreaks\_killstreaks::tryGiveKillstreak("airdrop_mega",        8);
        else if (self.menuIndex == 1) self maps\mp\killstreaks\_killstreaks::tryGiveKillstreak("helicopter_flares",   9);
        else if (self.menuIndex == 2) self maps\mp\killstreaks\_killstreaks::tryGiveKillstreak("stealth_airstrike",  9);
        else if (self.menuIndex == 3) self maps\mp\killstreaks\_killstreaks::tryGiveKillstreak("helicopter_minigun", 11);
        else if (self.menuIndex == 4) self maps\mp\killstreaks\_killstreaks::tryGiveKillstreak("ac130",             11);
        else if (self.menuIndex == 5) self maps\mp\killstreaks\_killstreaks::tryGiveKillstreak("emp",               15);
        else if (self.menuIndex == 6) self maps\mp\killstreaks\_killstreaks::tryGiveKillstreak("nuke",              25);
        else if (self.menuIndex == 7)
        {
            self.menuPage = "killstreaks";
            self.menuIndex = 9;
            self updateMenuHud();
            return;
        }
    }
    else if (self.menuPage == "perkhub")
    {
        if (self.menuIndex == 0)
        {
            self _setPerk("specialty_marathon");
            self _setPerk("specialty_fastmantle");
            self _setPerk("specialty_fastreload");
            self _setPerk("specialty_quickdraw");
            self _setPerk("specialty_scavenger");
            self _setPerk("specialty_extraammo");
            self _setPerk("specialty_bling");
            self _setPerk("specialty_secondarybling");
            self _setPerk("specialty_ONEMANARMY");
            self _setPerk("specialty_omaquickchange");
            self _setPerk("specialty_bulletdamage");
            self _setPerk("specialty_armorpiercing");
            self _setPerk("specialty_lightweight");
            self _setPerk("specialty_fastsprintrecovery");
            self _setPerk("specialty_hardline");
            self _setPerk("specialty_extraspecialduration");
            self _setPerk("specialty_coldblooded");
            self _setPerk("specialty_gpsjammer");
            self _setPerk("specialty_explosivedamage");
            self _setPerk("specialty_blackbox");
            self _setPerk("specialty_extendedmelee");
            self _setPerk("specialty_falldamage");
            self _setPerk("specialty_bulletaccuracy");
            self _setPerk("specialty_holdbreath");
            self _setPerk("specialty_localjammer");
            self _setPerk("specialty_delaymine");
            self _setPerk("specialty_NINJA");
            self _setPerk("specialty_quieter");
            self _setPerk("specialty_detectexplosive");
            self _setPerk("specialty_parabolic");
            self _setPerk("specialty_heartbreaker");
            self _setPerk("specialty_finalstand");
            self thread rainyShowRaisedMessage("^5All Pro Perks Given");
        }
        else if (self.menuIndex == 1)
        {
            self _unsetPerk("specialty_marathon");
            self _unsetPerk("specialty_fastmantle");
            self _unsetPerk("specialty_fastreload");
            self _unsetPerk("specialty_quickdraw");
            self _unsetPerk("specialty_scavenger");
            self _unsetPerk("specialty_extraammo");
            self _unsetPerk("specialty_bling");
            self _unsetPerk("specialty_secondarybling");
            self _unsetPerk("specialty_ONEMANARMY");
            self _unsetPerk("specialty_omaquickchange");
            self _unsetPerk("specialty_bulletdamage");
            self _unsetPerk("specialty_armorpiercing");
            self _unsetPerk("specialty_lightweight");
            self _unsetPerk("specialty_fastsprintrecovery");
            self _unsetPerk("specialty_hardline");
            self _unsetPerk("specialty_extraspecialduration");
            self _unsetPerk("specialty_coldblooded");
            self _unsetPerk("specialty_gpsjammer");
            self _unsetPerk("specialty_explosivedamage");
            self _unsetPerk("specialty_blackbox");
            self _unsetPerk("specialty_extendedmelee");
            self _unsetPerk("specialty_falldamage");
            self _unsetPerk("specialty_bulletaccuracy");
            self _unsetPerk("specialty_holdbreath");
            self _unsetPerk("specialty_localjammer");
            self _unsetPerk("specialty_delaymine");
            self _unsetPerk("specialty_NINJA");
            self _unsetPerk("specialty_quieter");
            self _unsetPerk("specialty_detectexplosive");
            self _unsetPerk("specialty_parabolic");
            self _unsetPerk("specialty_heartbreaker");
            self _unsetPerk("specialty_finalstand");
            self thread rainyShowRaisedMessage("^7All Perks Removed");
        }
        else if (self.menuIndex == 2)
        {
            self.menuPage = "giveperks";
            self.menuIndex = 0;
            self updateMenuHud();
            return;
        }
        else if (self.menuIndex == 3)
        {
            self.menuPage = "takeperks";
            self.menuIndex = 0;
            self updateMenuHud();
            return;
        }
    }
    else if (self.menuPage == "giveperks")
    {
        if (self.menuIndex == 0)
        {
            self _setPerk("specialty_marathon");
            self _setPerk("specialty_fastmantle");
            self thread rainyShowRaisedMessage("^5Perk Given");
        }
        else if (self.menuIndex == 1)
        {
            self _setPerk("specialty_fastreload");
            self _setPerk("specialty_quickdraw");
            self thread rainyShowRaisedMessage("^5Perk Given");
        }
        else if (self.menuIndex == 2)
        {
            self _setPerk("specialty_scavenger");
            self _setPerk("specialty_extraammo");
            self thread rainyShowRaisedMessage("^5Perk Given");
        }
        else if (self.menuIndex == 3)
        {
            self _setPerk("specialty_bling");
            self _setPerk("specialty_secondarybling");
            self thread rainyShowRaisedMessage("^5Perk Given");
        }
        else if (self.menuIndex == 4)
        {
            self _setPerk("specialty_ONEMANARMY");
            self _setPerk("specialty_omaquickchange");
            self thread rainyShowRaisedMessage("^5Perk Given");
        }
        else if (self.menuIndex == 5)
        {
            self _setPerk("specialty_bulletdamage");
            self _setPerk("specialty_armorpiercing");
            self thread rainyShowRaisedMessage("^5Perk Given");
        }
        else if (self.menuIndex == 6)
        {
            self _setPerk("specialty_lightweight");
            self _setPerk("specialty_fastsprintrecovery");
            self thread rainyShowRaisedMessage("^5Perk Given");
        }
        else if (self.menuIndex == 7)
        {
            self _setPerk("specialty_hardline");
            self _setPerk("specialty_extraspecialduration");
            self thread rainyShowRaisedMessage("^5Perk Given");
        }
        else if (self.menuIndex == 8)
        {
            self _setPerk("specialty_coldblooded");
            self _setPerk("specialty_gpsjammer");
            self thread rainyShowRaisedMessage("^5Perk Given");
        }
        else if (self.menuIndex == 9)
        {
            self.menuPage = "giveperks2";
            self.menuIndex = 0;
            self updateMenuHud();
            return;
        }
    }
    else if (self.menuPage == "giveperks2")
    {
        if (self.menuIndex == 0)
        {
            self _setPerk("specialty_explosivedamage");
            self _setPerk("specialty_blackbox");
            self thread rainyShowRaisedMessage("^7Perk Given");
        }
        else if (self.menuIndex == 1)
        {
            self _setPerk("specialty_extendedmelee");
            self _setPerk("specialty_falldamage");
            self thread rainyShowRaisedMessage("^7Perk Given");
        }
        else if (self.menuIndex == 2)
        {
            self _setPerk("specialty_bulletaccuracy");
            self _setPerk("specialty_holdbreath");
            self thread rainyShowRaisedMessage("^7Perk Given");
        }
        else if (self.menuIndex == 3)
        {
            self _setPerk("specialty_localjammer");
            self _setPerk("specialty_delaymine");
            self thread rainyShowRaisedMessage("^7Perk Given");
        }
        else if (self.menuIndex == 4)
        {
            self _setPerk("specialty_NINJA");
            self _setPerk("specialty_quieter");
            self thread rainyShowRaisedMessage("^7Perk Given");
        }
        else if (self.menuIndex == 5)
        {
            self _setPerk("specialty_detectexplosive");
            self _setPerk("specialty_parabolic");
            self thread rainyShowRaisedMessage("^7Perk Given");
        }
        else if (self.menuIndex == 6)
        {
            self _setPerk("specialty_heartbreaker");
            self _setPerk("specialty_finalstand");
            self thread rainyShowRaisedMessage("^7Perk Given");
        }
        else if (self.menuIndex == 7)
        {
            self.menuPage = "giveperks";
            self.menuIndex = 9;
            self updateMenuHud();
            return;
        }
    }
    else if (self.menuPage == "takeperks")
    {
        if (self.menuIndex == 0)
        {
            self _unsetPerk("specialty_marathon");
            self _unsetPerk("specialty_fastmantle");
            self thread rainyShowRaisedMessage("^5Perk Taken");
        }
        else if (self.menuIndex == 1)
        {
            self _unsetPerk("specialty_fastreload");
            self _unsetPerk("specialty_quickdraw");
            self thread rainyShowRaisedMessage("^5Perk Taken");
        }
        else if (self.menuIndex == 2)
        {
            self _unsetPerk("specialty_scavenger");
            self _unsetPerk("specialty_extraammo");
            self thread rainyShowRaisedMessage("^5Perk Taken");
        }
        else if (self.menuIndex == 3)
        {
            self _unsetPerk("specialty_bling");
            self _unsetPerk("specialty_secondarybling");
            self thread rainyShowRaisedMessage("^5Perk Taken");
        }
        else if (self.menuIndex == 4)
        {
            self _unsetPerk("specialty_ONEMANARMY");
            self _unsetPerk("specialty_omaquickchange");
            self thread rainyShowRaisedMessage("^5Perk Taken");
        }
        else if (self.menuIndex == 5)
        {
            self _unsetPerk("specialty_bulletdamage");
            self _unsetPerk("specialty_armorpiercing");
            self thread rainyShowRaisedMessage("^5Perk Taken");
        }
        else if (self.menuIndex == 6)
        {
            self _unsetPerk("specialty_lightweight");
            self _unsetPerk("specialty_fastsprintrecovery");
            self thread rainyShowRaisedMessage("^5Perk Taken");
        }
        else if (self.menuIndex == 7)
        {
            self _unsetPerk("specialty_hardline");
            self _unsetPerk("specialty_extraspecialduration");
            self thread rainyShowRaisedMessage("^5Perk Taken");
        }
        else if (self.menuIndex == 8)
        {
            self _unsetPerk("specialty_coldblooded");
            self _unsetPerk("specialty_gpsjammer");
            self thread rainyShowRaisedMessage("^5Perk Taken");
        }
        else if (self.menuIndex == 9)
        {
            self.menuPage = "takeperks2";
            self.menuIndex = 0;
            self updateMenuHud();
            return;
        }
    }
    else if (self.menuPage == "takeperks2")
    {
        if (self.menuIndex == 0)
        {
            self _unsetPerk("specialty_explosivedamage");
            self _unsetPerk("specialty_blackbox");
            self thread rainyShowRaisedMessage("^5Perk Taken");
        }
        else if (self.menuIndex == 1)
        {
            self _unsetPerk("specialty_extendedmelee");
            self _unsetPerk("specialty_falldamage");
            self thread rainyShowRaisedMessage("^5Perk Taken");
        }
        else if (self.menuIndex == 2)
        {
            self _unsetPerk("specialty_bulletaccuracy");
            self _unsetPerk("specialty_holdbreath");
            self thread rainyShowRaisedMessage("^5Perk Taken");
        }
        else if (self.menuIndex == 3)
        {
            self _unsetPerk("specialty_localjammer");
            self _unsetPerk("specialty_delaymine");
            self thread rainyShowRaisedMessage("^5Perk Taken");
        }
        else if (self.menuIndex == 4)
        {
            self _unsetPerk("specialty_NINJA");
            self _unsetPerk("specialty_quieter");
            self thread rainyShowRaisedMessage("^5Perk Taken");
        }
        else if (self.menuIndex == 5)
        {
            self _unsetPerk("specialty_detectexplosive");
            self _unsetPerk("specialty_parabolic");
            self thread rainyShowRaisedMessage("^5Perk Taken");
        }
        else if (self.menuIndex == 6)
        {
            self _unsetPerk("specialty_heartbreaker");
            self _unsetPerk("specialty_finalstand");
            self thread rainyShowRaisedMessage("^5Perk Taken");
        }
        else if (self.menuIndex == 7)
        {
            self.menuPage = "takeperks";
            self.menuIndex = 7;
            self updateMenuHud();
            return;
        }
    }
    else if (self.menuPage == "visions")
    {
        if (self.menuIndex == 0)
        {
            self setClientDvar("r_fullbright", "0");
            self rainyApplyFullbrightToAllPlayers("0");
            self visionSetNakedForPlayer("", 0.1);
            self rainyApplyVisionToAllPlayers("");
            self thread rainyShowRaisedMessage("^5None");
        }
        else if (self.menuIndex == 1)
        {
            self visionSetNakedForPlayer("", 0.1);
            self rainyApplyVisionToAllPlayers("");
            wait 0.1;
            // r_fullbright is a client-side render dvar, not a server dvar.
            // setDvar() here only ever forced it on the host's own client
            // instance (the host is a client too in a listen-server setup),
            // which is why other players never saw it. setClientDvar pushed
            // to every real player (bots excluded) fixes this.
            self setClientDvar("r_fullbright", "1");
            self rainyApplyFullbrightToAllPlayers("1");
            self thread rainyShowRaisedMessage("^7Fullbright");
        }
        else if (self.menuIndex == 2)
        {
            self setClientDvar("r_fullbright", "0");
            self rainyApplyFullbrightToAllPlayers("0");
            self visionSetNakedForPlayer("", 0.1);
            wait 0.1;
            self visionSetNakedForPlayer("ac130", 0.1);
            self rainyApplyVisionToAllPlayers("ac130");
            self thread rainyShowRaisedMessage("^5AC-130");
        }
        else if (self.menuIndex == 3)
        {
            self setClientDvar("r_fullbright", "0");
            self rainyApplyFullbrightToAllPlayers("0");
            self visionSetNakedForPlayer("", 0.1);
            wait 0.1;
            self visionSetNakedForPlayer("ac130_inverted", 0.1);
            self rainyApplyVisionToAllPlayers("ac130_inverted");
            self thread rainyShowRaisedMessage("^7AC-130 Inverted");
        }
        else if (self.menuIndex == 4)
        {
            self setClientDvar("r_fullbright", "0");
            self rainyApplyFullbrightToAllPlayers("0");
            self visionSetNakedForPlayer("", 0.1);
            wait 0.1;
            self visionSetNakedForPlayer("aftermath", 0.1);
            self rainyApplyVisionToAllPlayers("aftermath");
            self thread rainyShowRaisedMessage("^5Aftermath");
        }
        else if (self.menuIndex == 5)
        {
            self setClientDvar("r_fullbright", "0");
            self rainyApplyFullbrightToAllPlayers("0");
            self visionSetNakedForPlayer("", 0.1);
            wait 0.1;
            self visionSetNakedForPlayer("airplane", 0.1);
            self rainyApplyVisionToAllPlayers("airplane");
            self thread rainyShowRaisedMessage("^7Airplane");
        }
        else if (self.menuIndex == 6)
        {
            self setClientDvar("r_fullbright", "0");
            self rainyApplyFullbrightToAllPlayers("0");
            self visionSetNakedForPlayer("", 0.1);
            wait 0.1;
            self visionSetNakedForPlayer("airport", 0.1);
            self rainyApplyVisionToAllPlayers("airport");
            self thread rainyShowRaisedMessage("^5Airport");
        }
        else if (self.menuIndex == 7)
        {
            self setClientDvar("r_fullbright", "0");
            self rainyApplyFullbrightToAllPlayers("0");
            self visionSetNakedForPlayer("", 0.1);
            wait 0.1;
            self visionSetNakedForPlayer("airport_death", 0.1);
            self rainyApplyVisionToAllPlayers("airport_death");
            self thread rainyShowRaisedMessage("^7Airport Death");
        }
        else if (self.menuIndex == 8)
        {
            self setClientDvar("r_fullbright", "0");
            self rainyApplyFullbrightToAllPlayers("0");
            self visionSetNakedForPlayer("", 0.1);
            wait 0.1;
            self visionSetNakedForPlayer("airport_exterior", 0.1);
            self rainyApplyVisionToAllPlayers("airport_exterior");
            self thread rainyShowRaisedMessage("^5Airport Exterior");
        }
        else if (self.menuIndex == 9)
        {
            self.menuPage = "visions2";
            self.menuIndex = 0;
            self updateMenuHud();
            return;
        }
    }
    else if (self.menuPage == "visions2")
    {
        if (self.menuIndex == 0)
        {
            self setClientDvar("r_fullbright", "0");
            self rainyApplyFullbrightToAllPlayers("0");
            self visionSetNakedForPlayer("", 0.1);
            wait 0.1;
            self visionSetNakedForPlayer("airport_green", 0.1);
            self rainyApplyVisionToAllPlayers("airport_green");
            self thread rainyShowRaisedMessage("^5Airport Green");
        }
        else if (self.menuIndex == 1)
        {
            self setClientDvar("r_fullbright", "0");
            self rainyApplyFullbrightToAllPlayers("0");
            self visionSetNakedForPlayer("", 0.1);
            wait 0.1;
            self visionSetNakedForPlayer("airport_intro", 0.1);
            self rainyApplyVisionToAllPlayers("airport_intro");
            self thread rainyShowRaisedMessage("^7Airport Intro");
        }
        else if (self.menuIndex == 2)
        {
            self setClientDvar("r_fullbright", "0");
            self rainyApplyFullbrightToAllPlayers("0");
            self visionSetNakedForPlayer("", 0.1);
            wait 0.1;
            self visionSetNakedForPlayer("airport_stairs", 0.1);
            self rainyApplyVisionToAllPlayers("airport_stairs");
            self thread rainyShowRaisedMessage("^5Airport Stairs");
        }
        else if (self.menuIndex == 3)
        {
            self setClientDvar("r_fullbright", "0");
            self rainyApplyFullbrightToAllPlayers("0");
            self visionSetNakedForPlayer("", 0.1);
            wait 0.1;
            self visionSetNakedForPlayer("ambush", 0.1);
            self rainyApplyVisionToAllPlayers("ambush");
            self thread rainyShowRaisedMessage("^7Ambush");
        }
        else if (self.menuIndex == 4)
        {
            self setClientDvar("r_fullbright", "0");
            self rainyApplyFullbrightToAllPlayers("0");
            self visionSetNakedForPlayer("", 0.1);
            wait 0.1;
            self visionSetNakedForPlayer("armada", 0.1);
            self rainyApplyVisionToAllPlayers("armada");
            self thread rainyShowRaisedMessage("^5Armada");
        }
        else if (self.menuIndex == 5)
        {
            self setClientDvar("r_fullbright", "0");
            self rainyApplyFullbrightToAllPlayers("0");
            self visionSetNakedForPlayer("", 0.1);
            wait 0.1;
            self visionSetNakedForPlayer("armada_water", 0.1);
            self rainyApplyVisionToAllPlayers("armada_water");
            self thread rainyShowRaisedMessage("^7Armada Water");
        }
        else if (self.menuIndex == 6)
        {
            self setClientDvar("r_fullbright", "0");
            self rainyApplyFullbrightToAllPlayers("0");
            self visionSetNakedForPlayer("", 0.1);
            wait 0.1;
            self visionSetNakedForPlayer("bigcity_destroyed", 0.1);
            self rainyApplyVisionToAllPlayers("bigcity_destroyed");
            self thread rainyShowRaisedMessage("^5Big City Destroyed");
        }
        else if (self.menuIndex == 7)
        {
            self setClientDvar("r_fullbright", "0");
            self rainyApplyFullbrightToAllPlayers("0");
            self visionSetNakedForPlayer("", 0.1);
            wait 0.1;
            self visionSetNakedForPlayer("blackout", 0.1);
            self rainyApplyVisionToAllPlayers("blackout");
            self thread rainyShowRaisedMessage("^7Blackout");
        }
        else if (self.menuIndex == 8)
        {
            self setClientDvar("r_fullbright", "0");
            self rainyApplyFullbrightToAllPlayers("0");
            self visionSetNakedForPlayer("", 0.1);
            wait 0.1;
            self visionSetNakedForPlayer("blackout_nvg", 0.1);
            self rainyApplyVisionToAllPlayers("blackout_nvg");
            self thread rainyShowRaisedMessage("^5Blackout NVG");
        }
        else if (self.menuIndex == 9)
        {
            self.menuPage = "visions3";
            self.menuIndex = 0;
            self updateMenuHud();
            return;
        }
    }
    else if (self.menuPage == "visions3")
    {
        if (self.menuIndex == 0)
        {
            self setClientDvar("r_fullbright", "0");
            self rainyApplyFullbrightToAllPlayers("0");
            self visionSetNakedForPlayer("", 0.1);
            wait 0.1;
            self visionSetNakedForPlayer("bog", 0.1);
            self rainyApplyVisionToAllPlayers("bog");
            self thread rainyShowRaisedMessage("^5Bog");
        }
        else if (self.menuIndex == 1)
        {
            self setClientDvar("r_fullbright", "0");
            self rainyApplyFullbrightToAllPlayers("0");
            self visionSetNakedForPlayer("", 0.1);
            wait 0.1;
            self visionSetNakedForPlayer("boneyard", 0.1);
            self rainyApplyVisionToAllPlayers("boneyard");
            self thread rainyShowRaisedMessage("^7Boneyard");
        }
        else if (self.menuIndex == 2)
        {
            self setClientDvar("r_fullbright", "0");
            self rainyApplyFullbrightToAllPlayers("0");
            self visionSetNakedForPlayer("", 0.1);
            wait 0.1;
            self visionSetNakedForPlayer("bridge", 0.1);
            self rainyApplyVisionToAllPlayers("bridge");
            self thread rainyShowRaisedMessage("^5Bridge");
        }
        else if (self.menuIndex == 3)
        {
            self setClientDvar("r_fullbright", "0");
            self rainyApplyFullbrightToAllPlayers("0");
            self visionSetNakedForPlayer("", 0.1);
            wait 0.1;
            self visionSetNakedForPlayer("cargoship", 0.1);
            self rainyApplyVisionToAllPlayers("cargoship");
            self thread rainyShowRaisedMessage("^7Cargo Ship");
        }
        else if (self.menuIndex == 4)
        {
            self setClientDvar("r_fullbright", "0");
            self rainyApplyFullbrightToAllPlayers("0");
            self visionSetNakedForPlayer("", 0.1);
            wait 0.1;
            self visionSetNakedForPlayer("cheat_bw", 0.1);
            self rainyApplyVisionToAllPlayers("cheat_bw");
            self thread rainyShowRaisedMessage("^5Cheat BW");
        }
        else if (self.menuIndex == 5)
        {
            self setClientDvar("r_fullbright", "0");
            self rainyApplyFullbrightToAllPlayers("0");
            self visionSetNakedForPlayer("", 0.1);
            wait 0.1;
            self visionSetNakedForPlayer("cheat_bw_contrast", 0.1);
            self rainyApplyVisionToAllPlayers("cheat_bw_contrast");
            self thread rainyShowRaisedMessage("^7Cheat BW Contrast");
        }
        else if (self.menuIndex == 6)
        {
            self setClientDvar("r_fullbright", "0");
            self rainyApplyFullbrightToAllPlayers("0");
            self visionSetNakedForPlayer("", 0.1);
            wait 0.1;
            self visionSetNakedForPlayer("cheat_bw_invert", 0.1);
            self rainyApplyVisionToAllPlayers("cheat_bw_invert");
            self thread rainyShowRaisedMessage("^5Cheat BW Invert");
        }
        else if (self.menuIndex == 7)
        {
            self setClientDvar("r_fullbright", "0");
            self rainyApplyFullbrightToAllPlayers("0");
            self visionSetNakedForPlayer("", 0.1);
            wait 0.1;
            self visionSetNakedForPlayer("cheat_chaplinnight", 0.1);
            self rainyApplyVisionToAllPlayers("cheat_chaplinnight");
            self thread rainyShowRaisedMessage("^7Cheat Chaplin Night");
        }
        else if (self.menuIndex == 8)
        {
            self setClientDvar("r_fullbright", "0");
            self rainyApplyFullbrightToAllPlayers("0");
            self visionSetNakedForPlayer("", 0.1);
            wait 0.1;
            self visionSetNakedForPlayer("cheat_contrast", 0.1);
            self rainyApplyVisionToAllPlayers("cheat_contrast");
            self thread rainyShowRaisedMessage("^5Cheat Contrast");
        }
        else if (self.menuIndex == 9)
        {
            self.menuPage = "visions4";
            self.menuIndex = 0;
            self updateMenuHud();
            return;
        }
    }
    else if (self.menuPage == "visions4")
    {
        if (self.menuIndex == 0)
        {
            self setClientDvar("r_fullbright", "0");
            self rainyApplyFullbrightToAllPlayers("0");
            self visionSetNakedForPlayer("", 0.1);
            wait 0.1;
            self visionSetNakedForPlayer("cheat_invert", 0.1);
            self rainyApplyVisionToAllPlayers("cheat_invert");
            self thread rainyShowRaisedMessage("^5Cheat Invert");
        }
        else if (self.menuIndex == 1)
        {
            self setClientDvar("r_fullbright", "0");
            self rainyApplyFullbrightToAllPlayers("0");
            self visionSetNakedForPlayer("", 0.1);
            wait 0.1;
            self visionSetNakedForPlayer("cheat_invert_contrast", 0.1);
            self rainyApplyVisionToAllPlayers("cheat_invert_contrast");
            self thread rainyShowRaisedMessage("^7Cheat Invert Contrast");
        }
        else if (self.menuIndex == 2)
        {
            self setClientDvar("r_fullbright", "0");
            self rainyApplyFullbrightToAllPlayers("0");
            self visionSetNakedForPlayer("", 0.1);
            wait 0.1;
            self visionSetNakedForPlayer("cliffhanger", 0.1);
            self rainyApplyVisionToAllPlayers("cliffhanger");
            self thread rainyShowRaisedMessage("^5Cliff Hanger");
        }
        else if (self.menuIndex == 3)
        {
            self setClientDvar("r_fullbright", "0");
            self rainyApplyFullbrightToAllPlayers("0");
            self visionSetNakedForPlayer("", 0.1);
            wait 0.1;
            self visionSetNakedForPlayer("dcemp", 0.1);
            self rainyApplyVisionToAllPlayers("dcemp");
            self thread rainyShowRaisedMessage("^7DC");
        }
        else if (self.menuIndex == 4)
        {
            self setClientDvar("r_fullbright", "0");
            self rainyApplyFullbrightToAllPlayers("0");
            self visionSetNakedForPlayer("", 0.1);
            wait 0.1;
            self visionSetNakedForPlayer("dcemp_emp", 0.1);
            self rainyApplyVisionToAllPlayers("dcemp_emp");
            self thread rainyShowRaisedMessage("^5DC EMP");
        }
        else if (self.menuIndex == 5)
        {
            self setClientDvar("r_fullbright", "0");
            self rainyApplyFullbrightToAllPlayers("0");
            self visionSetNakedForPlayer("", 0.1);
            wait 0.1;
            self visionSetNakedForPlayer("default", 0.1);
            self rainyApplyVisionToAllPlayers("default");
            self thread rainyShowRaisedMessage("^7Default");
        }
        else if (self.menuIndex == 6)
        {
            self setClientDvar("r_fullbright", "0");
            self rainyApplyFullbrightToAllPlayers("0");
            self visionSetNakedForPlayer("", 0.1);
            wait 0.1;
            self visionSetNakedForPlayer("default_night", 0.1);
            self rainyApplyVisionToAllPlayers("default_night");
            self thread rainyShowRaisedMessage("^5Default Night");
        }
        else if (self.menuIndex == 7)
        {
            self setClientDvar("r_fullbright", "0");
            self rainyApplyFullbrightToAllPlayers("0");
            self visionSetNakedForPlayer("", 0.1);
            wait 0.1;
            self visionSetNakedForPlayer("default_night_mp", 0.1);
            self rainyApplyVisionToAllPlayers("default_night_mp");
            self thread rainyShowRaisedMessage("^7Default Night MP");
        }
        else if (self.menuIndex == 8)
        {
            self setClientDvar("r_fullbright", "0");
            self rainyApplyFullbrightToAllPlayers("0");
            self visionSetNakedForPlayer("", 0.1);
            wait 0.1;
            self visionSetNakedForPlayer("end_game", 0.1);
            self rainyApplyVisionToAllPlayers("end_game");
            self thread rainyShowRaisedMessage("^5End Game");
        }
        else if (self.menuIndex == 9)
        {
            self.menuPage = "visions5";
            self.menuIndex = 0;
            self updateMenuHud();
            return;
        }
    }
    else if (self.menuPage == "visions5")
    {
        if (self.menuIndex == 0)
        {
            self setClientDvar("r_fullbright", "0");
            self rainyApplyFullbrightToAllPlayers("0");
            self visionSetNakedForPlayer("", 0.1);
            wait 0.1;
            self visionSetNakedForPlayer("introscreen", 0.1);
            self rainyApplyVisionToAllPlayers("introscreen");
            self thread rainyShowRaisedMessage("^5Intro Screen");
        }
        else if (self.menuIndex == 1)
        {
            self setClientDvar("r_fullbright", "0");
            self rainyApplyFullbrightToAllPlayers("0");
            self visionSetNakedForPlayer("", 0.1);
            wait 0.1;
            self visionSetNakedForPlayer("mp_afghan", 0.1);
            self rainyApplyVisionToAllPlayers("mp_afghan");
            self thread rainyShowRaisedMessage("^7MP Afghan");
        }
        else if (self.menuIndex == 2)
        {
            self setClientDvar("r_fullbright", "0");
            self rainyApplyFullbrightToAllPlayers("0");
            self visionSetNakedForPlayer("", 0.1);
            wait 0.1;
            self visionSetNakedForPlayer("mpnuke", 0.1);
            self rainyApplyVisionToAllPlayers("mpnuke");
            self thread rainyShowRaisedMessage("^5MP Nuke");
        }
        else if (self.menuIndex == 3)
        {
            self setClientDvar("r_fullbright", "0");
            self rainyApplyFullbrightToAllPlayers("0");
            self visionSetNakedForPlayer("", 0.1);
            wait 0.1;
            self visionSetNakedForPlayer("mpnuke_aftermath", 0.1);
            self rainyApplyVisionToAllPlayers("mpnuke_aftermath");
            self thread rainyShowRaisedMessage("^7MP Nuke Aftermath");
        }
        else if (self.menuIndex == 4)
        {
            self setClientDvar("r_fullbright", "0");
            self rainyApplyFullbrightToAllPlayers("0");
            self visionSetNakedForPlayer("", 0.1);
            wait 0.1;
            self visionSetNakedForPlayer("mpoutro", 0.1);
            self rainyApplyVisionToAllPlayers("mpoutro");
            self thread rainyShowRaisedMessage("^5MP Outro");
        }
        else if (self.menuIndex == 5)
        {
            self setClientDvar("r_fullbright", "0");
            self rainyApplyFullbrightToAllPlayers("0");
            self visionSetNakedForPlayer("", 0.1);
            wait 0.1;
            self visionSetNakedForPlayer("near_death", 0.1);
            self rainyApplyVisionToAllPlayers("near_death");
            self thread rainyShowRaisedMessage("^7Near Death");
        }
        else if (self.menuIndex == 6)
        {
            self setClientDvar("r_fullbright", "0");
            self rainyApplyFullbrightToAllPlayers("0");
            self visionSetNakedForPlayer("", 0.1);
            wait 0.1;
            self visionSetNakedForPlayer("near_death_mp", 0.1);
            self rainyApplyVisionToAllPlayers("near_death_mp");
            self thread rainyShowRaisedMessage("^5Near Death MP");
        }
        else if (self.menuIndex == 7)
        {
            self setClientDvar("r_fullbright", "0");
            self rainyApplyFullbrightToAllPlayers("0");
            self visionSetNakedForPlayer("", 0.1);
            wait 0.1;
            self visionSetNakedForPlayer("thermal_mp", 0.1);
            self rainyApplyVisionToAllPlayers("thermal_mp");
            self thread rainyShowRaisedMessage("^7Thermal MP");
        }
        else if (self.menuIndex == 8)
        {
            self.menuPage = "visions";
            self.menuIndex = 0;
            self updateMenuHud();
            return;
        }
    }
    else if (self.menuPage == "giveweapons")
    {
        if (self.menuIndex == 0)
        {
            self.menuPage = "snipers";
            self.menuIndex = 0;
            self updateMenuHud();
            return;
        }
        else if (self.menuIndex == 1)
        {
            self.menuPage = "handguns";
            self.menuIndex = 0;
            self updateMenuHud();
            return;
        }
        else if (self.menuIndex == 2)
        {
            self.menuPage = "shotguns";
            self.menuIndex = 0;
            self updateMenuHud();
            return;
        }
        else if (self.menuIndex == 3)
        {
            self.menuPage = "machinepistols";
            self.menuIndex = 0;
            self updateMenuHud();
            return;
        }
        else if (self.menuIndex == 4)
        {
            self.menuPage = "assaultrifles";
            self.menuIndex = 0;
            self updateMenuHud();
            return;
        }
        else if (self.menuIndex == 5)
        {
            self.menuPage = "smgs";
            self.menuIndex = 0;
            self updateMenuHud();
            return;
        }
        else if (self.menuIndex == 6)
        {
            self.menuPage = "lmgs";
            self.menuIndex = 0;
            self updateMenuHud();
            return;
        }
        else if (self.menuIndex == 7)
        {
            self.menuPage = "specials";
            self.menuIndex = 0;
            self updateMenuHud();
            return;
        }
        else if (self.menuIndex == 8)
        {
            self.menuPage = "lethals";
            self.menuIndex = 0;
            self updateMenuHud();
            return;
        }
        else if (self.menuIndex == 9)
        {
            self.menuPage = "tacticals";
            self.menuIndex = 0;
            self updateMenuHud();
            return;
        }
    }
    else if (self.menuPage == "snipers")
    {
        if (self.menuIndex == 0)
        {
            self giveMenuWeapon("cheytac_mp", "Intervention");
        }
        else if (self.menuIndex == 1)
        {
            self giveMenuWeapon("barrett_mp", "Barrett .50cal");
        }
        else if (self.menuIndex == 2)
        {
            self giveMenuWeapon("wa2000_mp", "WA2000");
        }
        else if (self.menuIndex == 3)
        {
            self giveMenuWeapon("m21_mp", "M21 EBR");
        }
        else if (self.menuIndex == 4)
        {
            self giveMenuWeapon("m40a3_mp", "M40A3");
        }
        else if (self.menuIndex == 5)
        {
            self giveMenuWeapon("dragunov_mp", "Dragunov");
        }
    }
    else if (self.menuPage == "handguns")
    {
        if (self.menuIndex == 0)
        {
            self giveMenuWeapon("usp_mp", "USP .45");
        }
        else if (self.menuIndex == 1)
        {
            self giveMenuWeapon("coltanaconda_mp", "Magnum");
        }
        else if (self.menuIndex == 2)
        {
            self giveMenuWeapon("beretta_mp", "M9");
        }
        else if (self.menuIndex == 3)
        {
            self giveMenuWeapon("deserteagle_mp", "Desert Eagle");
        }
        else if (self.menuIndex == 4)
        {
            self giveMenuWeapon("deserteaglegold_mp", "Gold Desert Eagle");
        }
    }
    else if (self.menuPage == "shotguns")
    {
        if (self.menuIndex == 0)
        {
            self giveMenuWeapon("spas12_mp", "SPAS-12");
        }
        else if (self.menuIndex == 1)
        {
            self giveMenuWeapon("aa12_mp", "AA-12");
        }
        else if (self.menuIndex == 2)
        {
            self giveMenuWeapon("striker_mp", "Striker");
        }
        else if (self.menuIndex == 3)
        {
            self giveMenuWeapon("ranger_mp", "Ranger");
        }
        else if (self.menuIndex == 4)
        {
            self giveMenuWeapon("m1014_mp", "M1014");
        }
        else if (self.menuIndex == 5)
        {
            self giveMenuWeapon("model1887_mp", "Model 1887");
        }
    }
    else if (self.menuPage == "machinepistols")
    {
        if (self.menuIndex == 0)
        {
            self giveMenuWeapon("pp2000_mp", "PP2000");
        }
        else if (self.menuIndex == 1)
        {
            self giveMenuWeapon("glock_mp", "G18");
        }
        else if (self.menuIndex == 2)
        {
            self giveMenuWeapon("beretta393_mp", "M93 Raffica");
        }
        else if (self.menuIndex == 3)
        {
            self giveMenuWeapon("tmp_mp", "TMP");
        }
    }
    else if (self.menuPage == "assaultrifles")
    {
        if (self.menuIndex == 0)
        {
            self giveMenuWeapon("m4_mp", "M4A1");
        }
        else if (self.menuIndex == 1)
        {
            self giveMenuWeapon("famas_mp", "FAMAS");
        }
        else if (self.menuIndex == 2)
        {
            self giveMenuWeapon("scar_mp", "SCAR-H");
        }
        else if (self.menuIndex == 3)
        {
            self giveMenuWeapon("tavor_mp", "TAR-21");
        }
        else if (self.menuIndex == 4)
        {
            self giveMenuWeapon("fal_mp", "FAL");
        }
        else if (self.menuIndex == 5)
        {
            self giveMenuWeapon("m16_mp", "M16A4");
        }
        else if (self.menuIndex == 6)
        {
            self giveMenuWeapon("masada_mp", "ACR");
        }
        else if (self.menuIndex == 7)
        {
            self giveMenuWeapon("fn2000_mp", "F2000");
        }
        else if (self.menuIndex == 8)
        {
            self giveMenuWeapon("ak47_mp", "AK-47");
        }
        else if (self.menuIndex == 9)
        {
            self giveMenuWeapon("ak47classic_mp", "AK-47 Classic");
        }
    }
    else if (self.menuPage == "smgs")
    {
        if (self.menuIndex == 0)
        {
            self giveMenuWeapon("mp5k_mp", "MP5K");
        }
        else if (self.menuIndex == 1)
        {
            self giveMenuWeapon("ump45_mp", "UMP45");
        }
        else if (self.menuIndex == 2)
        {
            self giveMenuWeapon("kriss_mp", "Vector");
        }
        else if (self.menuIndex == 3)
        {
            self giveMenuWeapon("p90_mp", "P90");
        }
        else if (self.menuIndex == 4)
        {
            self giveMenuWeapon("uzi_mp", "Mini-Uzi");
        }
        else if (self.menuIndex == 5)
        {
            self giveMenuWeapon("ak74u_mp", "AK-74u");
        }
        else if (self.menuIndex == 6)
        {
            self giveMenuWeapon("peacekeeper_mp", "Peacekeeper");
        }
    }
    else if (self.menuPage == "lmgs")
    {
        if (self.menuIndex == 0)
        {
            self giveMenuWeapon("sa80_mp", "L86 LSW");
        }
        else if (self.menuIndex == 1)
        {
            self giveMenuWeapon("rpd_mp", "RPD");
        }
        else if (self.menuIndex == 2)
        {
            self giveMenuWeapon("mg4_mp", "MG4");
        }
        else if (self.menuIndex == 3)
        {
            self giveMenuWeapon("aug_mp", "AUG HBAR");
        }
        else if (self.menuIndex == 4)
        {
            self giveMenuWeapon("m240_mp", "M240");
        }
    }
    else if (self.menuPage == "attachments")
    {
        if (!isDefined(self.attachCount) || self.attachCount == 0)
            return;
        if (self.menuIndex == 0 && isDefined(self.attachKey0)) self equipMenuAttachment(self.attachKey0);
        else if (self.menuIndex == 1 && isDefined(self.attachKey1)) self equipMenuAttachment(self.attachKey1);
        else if (self.menuIndex == 2 && isDefined(self.attachKey2)) self equipMenuAttachment(self.attachKey2);
        else if (self.menuIndex == 3 && isDefined(self.attachKey3)) self equipMenuAttachment(self.attachKey3);
        else if (self.menuIndex == 4 && isDefined(self.attachKey4)) self equipMenuAttachment(self.attachKey4);
        else if (self.menuIndex == 5 && isDefined(self.attachKey5)) self equipMenuAttachment(self.attachKey5);
        else if (self.menuIndex == 6 && isDefined(self.attachKey6)) self equipMenuAttachment(self.attachKey6);
        else if (self.menuIndex == 7 && isDefined(self.attachKey7)) self equipMenuAttachment(self.attachKey7);
        else if (self.menuIndex == 8 && isDefined(self.attachKey8)) self equipMenuAttachment(self.attachKey8);
        else if (self.menuIndex == 9 && isDefined(self.attachKey9)) self equipMenuAttachment(self.attachKey9);
    }
    else if (self.menuPage == "specials")
    {
        if (self.menuIndex == 0)
        {
            self giveMenuWeapon("riotshield_mp", "Riot Shield");
        }
        else if (self.menuIndex == 1)
        {
            self.menuPage = "launchers";
            self.menuIndex = 0;
            self updateMenuHud();
            return;
        }
    }
    else if (self.menuPage == "launchers")
    {
        if (self.menuIndex == 0)
        {
            self giveMenuWeapon("at4_mp", "AT4-HS");
        }
        else if (self.menuIndex == 1)
        {
            self giveMenuWeapon("m79_mp", "Thumper");
        }
        else if (self.menuIndex == 2)
        {
            self giveMenuWeapon("stinger_mp", "Stinger");
        }
        else if (self.menuIndex == 3)
        {
            self giveMenuWeapon("javelin_mp", "Javelin");
        }
        else if (self.menuIndex == 4)
        {
            self giveMenuWeapon("rpg_mp", "RPG-7");
        }
    }
    else if (self.menuPage == "lethals")
    {
        if (self.menuIndex == 0)
        {
            self giveMenuWeapon("frag_grenade_mp", "Frag Grenade");
        }
        else if (self.menuIndex == 1)
        {
            self giveMenuWeapon("semtex_mp", "Semtex");
        }
        else if (self.menuIndex == 2)
        {
            self giveMenuWeapon("throwingknife_mp", "Throwing Knife");
        }
        else if (self.menuIndex == 3)
        {
            self giveMenuWeapon("claymore_mp", "Claymore");
        }
        else if (self.menuIndex == 4)
        {
            self giveMenuWeapon("c4_mp", "C4");
        }
    }
    else if (self.menuPage == "tacticals")
    {
        if (self.menuIndex == 0)
        {
            self giveMenuWeapon("flash_grenade_mp", "Flash Grenade");
        }
        else if (self.menuIndex == 1)
        {
            self giveMenuWeapon("concussion_grenade_mp", "Stun Grenade");
        }
        else if (self.menuIndex == 2)
        {
            self giveMenuWeapon("smoke_grenade_mp", "Smoke Grenade");
        }
    }
    else if (self.menuPage == "mainmods")
    {
        if (self.menuIndex == 0)
        {
            self.menuPage = "trickshotmods";
            self.menuIndex = 0;
            self updateMenuHud();
            return;
        }
        else if (self.menuIndex == 1)
        {
            self savePosition();
        }
        else if (self.menuIndex == 2)
        {
            self loadPosition();
        }
        else if (self.menuIndex == 3)
        {
            self giveAmmoOnce();
        }
        else if (self.menuIndex == 4)
        {
            self toggleForceUAV();
        }
        else if (self.menuIndex == 5)
        {
            self toggleKillcams();
        }
        else if (self.menuIndex == 6)
        {
            self toggleGodMode();
        }
        else if (self.menuIndex == 7)
        {
            self toggleUFO();
        }
    }
    else if (self.menuPage == "bots")
    {
        if (self.menuIndex == 0)
        {
            self.menuPage = "addbots";
            self.menuIndex = 0;
            self updateMenuHud();
            return;
        }
        else if (self.menuIndex == 1)
        {
            self toggleFreezeBots();
        }
        else if (self.menuIndex == 2)
        {
            self thread bringBotsToPlayer();
        }
        else if (self.menuIndex == 3)
        {
            self thread bringBotsToCrosshair();
        }
        else if (self.menuIndex == 4)
        {
            self.menuPage = "teamsdifficulty";
            self.menuIndex = 0;
            self updateMenuHud();
            return;
        }
        else if (self.menuIndex == 5)
        {
            self togglePassiveBots();
        }
        else if (self.menuIndex == 6)
        {
            self thread scatterBotsToWaypoints();
        }
        else if (self.menuIndex == 7)
        {
            self toggleBotChat();
        }
        else if (self.menuIndex == 8)
        {
            self killAllBots();
        }
        else if (self.menuIndex == 9)
        {
            self thread kickAllBots();
        }
    }
    else if (self.menuPage == "teamsdifficulty")
    {
        if (self.menuIndex == 0)
        {
            self cycleBotTeam();
        }
        else if (self.menuIndex == 1)
        {
            self adjustAxisBotCount(1);
        }
        else if (self.menuIndex == 2)
        {
            self adjustAxisBotCount(-1);
        }
        else if (self.menuIndex == 3)
        {
            self toggleForceBotTeam();
        }
        else if (self.menuIndex == 4)
        {
            self toggleBotTeamTarget();
        }
        else if (self.menuIndex == 5)
        {
            self cycleBotDifficulty();
        }
    }
    else if (self.menuPage == "addbots")
    {
        if (self.menuIndex == 0)
        {
            self addBotsAmount(1);
        }
        else if (self.menuIndex == 1)
        {
            self addBotsAmount(3);
        }
        else if (self.menuIndex == 2)
        {
            self addBotsAmount(7);
        }
        else if (self.menuIndex == 3)
        {
            self addBotsAmount(11);
        }
        else if (self.menuIndex == 4)
        {
            self addBotsAmount(17);
        }
    }
    else if (self.menuPage == "lobby")
    {
        if (self.menuIndex == 0)
        {
            self.menuPage = "settime";
            self.menuIndex = 0;
            self updateMenuHud();
            return;
        }
        else if (self.menuIndex == 1)
        {
            self cyclePlayerHealth();
        }
        else if (self.menuIndex == 2)
        {
            self toggleTrickshotDamageOnly();
        }
        else if (self.menuIndex == 3)
        {
            self.menuPage = "setgamemode";
            self.menuIndex = 0;
            self updateMenuHud();
            return;
        }
        else if (self.menuIndex == 4)
        {
            self.menuPage = "setscore";
            self.menuIndex = 0;
            self updateMenuHud();
            return;
        }
        else if (self.menuIndex == 5)
        {
            self.menuPage = "tdmoptions";
            self.menuIndex = 0;
            self updateMenuHud();
            return;
        }
        else if (self.menuIndex == 6)
        {
            self rainyRestartGame();
        }
        else if (self.menuIndex == 7)
        {
            self rainyInstantEndGame();
        }
    }
    else if (self.menuPage == "setgamemode")
    {
        if (self.menuIndex == 0)
        {
            self rainyChangeGametype("dm");
        }
        else if (self.menuIndex == 1)
        {
            self rainyChangeGametype("war");
        }
        else if (self.menuIndex == 2)
        {
            self rainyChangeGametype("sd");
        }
    }
    else if (self.menuPage == "tdmoptions")
    {
        if (self.menuIndex == 0)
        {
            self toggleFriendlyFire();
        }
        else if (self.menuIndex == 1)
        {
            self friendlyTeamLastTDM();
        }
        else if (self.menuIndex == 2)
        {
            self enemyTeamLastTDM();
        }
        else if (self.menuIndex == 3)
        {
            self resetFriendlyScoreTDM();
        }
        else if (self.menuIndex == 4)
        {
            self resetEnemyScoreTDM();
        }
    }
    else if (self.menuPage == "settime")
    {
        if (self.menuIndex == 0)
        {
            self setMatchTime(0);
            self thread rainyShowRaisedMessage("^5Time Set To Unlimited");
        }
        else if (self.menuIndex == 1)
        {
            self addMatchTime(1);
        }
        else if (self.menuIndex == 2)
        {
            self addMatchTime(5);
        }
        else if (self.menuIndex == 3)
        {
            self addMatchTime(10);
        }
    }
    else if (self.menuPage == "setscore")
    {
        if (self.menuIndex == 0)
        {
            self.menuPage = "ffascore";
            self.menuIndex = 0;
            self updateMenuHud();
            return;
        }
        else if (self.menuIndex == 1)
        {
            self.menuPage = "tdmscore";
            self.menuIndex = 0;
            self updateMenuHud();
            return;
        }
    }
    else if (self.menuPage == "ffascore")
    {
        if (self.menuIndex == 0)
            self rainySetScoreLimit("dm", 0, "FFA");
        else if (self.menuIndex == 1)
            self rainySetScoreLimit("dm", 1000, "FFA");
        else if (self.menuIndex == 2)
            self rainySetScoreLimit("dm", 1500, "FFA");
        else if (self.menuIndex == 3)
            self rainySetScoreLimit("dm", 3000, "FFA");
    }
    else if (self.menuPage == "tdmscore")
    {
        if (self.menuIndex == 0)
            self rainySetScoreLimit("war", 0, "TDM");
        else if (self.menuIndex == 1)
            self rainySetScoreLimit("war", 2500, "TDM");
        else if (self.menuIndex == 2)
            self rainySetScoreLimit("war", 5000, "TDM");
        else if (self.menuIndex == 3)
            self rainySetScoreLimit("war", 7500, "TDM");
    }
    if (self.menuPage == "clients")
    {
        self rainyClientsMenuSelect();
        return;
    }
    if (self.menuPage == "allplayers")
    {
        if (self.menuIndex == 0)
            self rainyToggleAllAutoRefill();
        else if (self.menuIndex == 1)
            self rainyFastLastAllFFA();
        else if (self.menuIndex == 2)
            self thread rainyTeleportAllToMe();
        else if (self.menuIndex == 3)
            self thread rainyTeleportAllToCrosshair();
        else if (self.menuIndex == 4)
            self rainyToggleAllTsAimbot();
        else if (self.menuIndex == 5)
            self rainyFreezeAllPlayers();
        else if (self.menuIndex == 6)
            self rainyUnfreezeAllPlayers();
        else if (self.menuIndex == 7)
            self rainyKickAllPlayers();
        else if (self.menuIndex == 8)
            self rainyKillAllPlayers();
        else if (self.menuIndex == 9)
        {
            self.menuPage = "allplayers2";
            self.menuIndex = 0;
            self updateMenuHud();
            return;
        }
        // Refresh so the [ON]/[OFF] toggles update in place.
        if (isDefined(self.menuOpen) && self.menuOpen)
            self updateMenuHud();
        return;
    }
    if (self.menuPage == "allplayers2")
    {
        if (self.menuIndex == 0)
            self rainyToggleAllGodMode();
        else if (self.menuIndex == 1)
            self rainyResetAllFFAScore();
        else if (self.menuIndex == 2)
            self rainyToggleAllCanswap();
        else if (self.menuIndex == 3)
        {
            self.menuPage = "allplayers";
            self.menuIndex = 9;
            self updateMenuHud();
            return;
        }
        // Refresh so the [ON]/[OFF] toggles update in place.
        if (isDefined(self.menuOpen) && self.menuOpen)
            self updateMenuHud();
        return;
    }
    if (isSubStr(self.menuPage, "clientsub_"))
    {
        if (self.menuIndex == 0)
            self rainyToggleClientAutoRefill();
        else if (self.menuIndex == 1)
            self rainyClientFastLast();
        else if (self.menuIndex == 2)
            self thread rainyTeleportClientToMe();
        else if (self.menuIndex == 3)
            self thread rainyTeleportClientToCrosshair();
        else if (self.menuIndex == 4)
            self rainyToggleClientTsAimbot();
        else if (self.menuIndex == 5)
            self rainyFreezeClient();
        else if (self.menuIndex == 6)
            self rainyUnfreezeClient();
        else if (self.menuIndex == 7)
            self rainyKickClient();
        else if (self.menuIndex == 8)
            self rainyKillClient();
        else if (self.menuIndex == 9)
        {
            target9 = self.clientSubTarget;
            self.menuPage = "clientsub2_" + target9 getEntityNumber();
            self.menuIndex = 0;
            self updateMenuHud();
            return;
        }
        // Refresh so the per-player [ON]/[OFF] toggles update in place.
        if (isDefined(self.menuOpen) && self.menuOpen)
            self updateMenuHud();
        return;
    }
    if (isSubStr(self.menuPage, "clientsub2_"))
    {
        if (self.menuIndex == 0)
            self rainyToggleClientGodMode();
        else if (self.menuIndex == 1)
            self rainyClientResetFFAScore();
        else if (self.menuIndex == 2)
            self thread rainyToggleClientCanswap();
        else if (self.menuIndex == 3)
        {
            target2back = self.clientSubTarget;
            self.menuPage = "clientsub_" + target2back getEntityNumber();
            self.menuIndex = 9;
            self updateMenuHud();
            return;
        }
        // Refresh so the per-player [ON]/[OFF] toggles update in place.
        if (isDefined(self.menuOpen) && self.menuOpen)
            self updateMenuHud();
        return;
    }
    if (isDefined(self.menuOpen) && self.menuOpen)
        self updateMenuHud();
}
loadAttachmentsForWeapon()
{
    self.attachCount = 0;
    self.attach0 = undefined; self.attachKey0 = undefined;
    self.attach1 = undefined; self.attachKey1 = undefined;
    self.attach2 = undefined; self.attachKey2 = undefined;
    self.attach3 = undefined; self.attachKey3 = undefined;
    self.attach4 = undefined; self.attachKey4 = undefined;
    self.attach5 = undefined; self.attachKey5 = undefined;
    self.attach6 = undefined; self.attachKey6 = undefined;
    self.attach7 = undefined; self.attachKey7 = undefined;
    self.attach8 = undefined; self.attachKey8 = undefined;
    self.attach9 = undefined; self.attachKey9 = undefined;
    currentWeapon = self getCurrentWeapon();
    if (!isDefined(currentWeapon) || currentWeapon == "none")
        return;
    weaponParts = strTok(currentWeapon, "_");
    baseName = weaponParts[0];
    count = 0;
    for (i = 11; i < 30; i++)
    {
        key = tableLookup("mp/statsTable.csv", 4, baseName, i);
        if (!isDefined(key) || key == "")
            break;
        if (count >= 10)
            break;
        displayName = key;
        if (key == "reflex")    displayName = "Reflex Sight";
        else if (key == "eotech")    displayName = "Holographic Sight";
        else if (key == "acog")      displayName = "ACOG Scope";
        else if (key == "thermal")   displayName = "Thermal Scope";
        else if (key == "grip")      displayName = "Grip";
        else if (key == "gl")        displayName = "Grenade Launcher";
        else if (key == "shotgun")   displayName = "Shotgun";
        else if (key == "tactical")  displayName = "Tactical Knife";
        else if (key == "heartbeat") displayName = "Heartbeat Sensor";
        else if (key == "silencer")  displayName = "Silencer";
        else if (key == "xmags")     displayName = "Extended Mags";
        else if (key == "rof")       displayName = "Rapid Fire";
        else if (key == "akimbo")    displayName = "Akimbo";
        else if (key == "fmj")       displayName = "FMJ";
        if (count == 0) { self.attach0 = displayName; self.attachKey0 = key; }
        else if (count == 1) { self.attach1 = displayName; self.attachKey1 = key; }
        else if (count == 2) { self.attach2 = displayName; self.attachKey2 = key; }
        else if (count == 3) { self.attach3 = displayName; self.attachKey3 = key; }
        else if (count == 4) { self.attach4 = displayName; self.attachKey4 = key; }
        else if (count == 5) { self.attach5 = displayName; self.attachKey5 = key; }
        else if (count == 6) { self.attach6 = displayName; self.attachKey6 = key; }
        else if (count == 7) { self.attach7 = displayName; self.attachKey7 = key; }
        else if (count == 8) { self.attach8 = displayName; self.attachKey8 = key; }
        else if (count == 9) { self.attach9 = displayName; self.attachKey9 = key; }
        count++;
    }
    self.attachCount = count;
}
equipMenuAttachment(attachment)
{
    weapon = getBaseWeaponName(self getCurrentWeapon());
    weaponSplit = strTok(self getCurrentWeapon(), "_");
    weaponAttach1 = undefined;
    weaponAttach2 = undefined;
    knownAttachments = [];
    knownAttachments[0] = "reflex";
    knownAttachments[1] = "eotech";
    knownAttachments[2] = "acog";
    knownAttachments[3] = "thermal";
    knownAttachments[4] = "grip";
    knownAttachments[5] = "gl";
    knownAttachments[6] = "shotgun";
    knownAttachments[7] = "tactical";
    knownAttachments[8] = "heartbeat";
    knownAttachments[9] = "silencer";
    knownAttachments[10] = "xmags";
    knownAttachments[11] = "rof";
    knownAttachments[12] = "akimbo";
    knownAttachments[13] = "fmj";
    if (weaponSplit.size > 1)
    {
        for (i = 2; i < weaponSplit.size; i++)
        {
            if (!isDefined(weaponSplit[i]) || weaponSplit[i] == "mp")
                continue;
            for (j = 0; j < knownAttachments.size; j++)
            {
                if (weaponSplit[i] == knownAttachments[j])
                {
                    if (!isDefined(weaponAttach1))
                        weaponAttach1 = weaponSplit[i];
                    else if (!isDefined(weaponAttach2))
                        weaponAttach2 = weaponSplit[i];
                    break;
                }
            }
        }
    }
    if (!isDefined(weaponAttach1))
        weaponAttach1 = attachment;
    else if (!isDefined(weaponAttach2))
        weaponAttach2 = attachment;
    if (!isDefined(weaponAttach1))
        weaponAttach1 = "none";
    if (!isDefined(weaponAttach2))
        weaponAttach2 = "none";
    weaponAttached = maps\mp\gametypes\_class::buildWeaponName(weapon, weaponAttach1, weaponAttach2);
    camoIdx = 0;
    if (isDefined(self.rainyCamoByWeapon) && isDefined(self.rainyCamoByWeapon[weapon]))
        camoIdx = self.rainyCamoByWeapon[weapon];
    else if (isDefined(self.rainyCamoIndex))
        camoIdx = self.rainyCamoIndex;
    self takeWeapon(self getCurrentWeapon());
    self _giveWeapon(weaponAttached, camoIdx);
    self switchToWeaponImmediate(weaponAttached);
    self setWeaponAmmoClip(weaponAttached, 999);
    self setWeaponAmmoStock(weaponAttached, 999);
    if (self.menuIndex % 2 == 0)
        self thread rainyShowRaisedMessage("^5Attachment equipped");
    else
        self thread rainyShowRaisedMessage("^7Attachment equipped");
}
allowClassChangeAlways()
{
    self endon("disconnect");
    level endon("game_ended");
    level endon("rainy_shutdown");
    game["strings"]["change_class"] = "";
    lastClass = "";
    if (isDefined(self.pers["class"]))
        lastClass = self.pers["class"];
    for (;;)
    {
        wait 0.1;
        if (!isDefined(self.pers["class"]))
            continue;
        currentClass = self.pers["class"];
        if (currentClass != lastClass && currentClass != "")
        {
            lastClass = currentClass;
            if (isAlive(self))
            {
                playerTeam = self.pers["team"];
                if (!isDefined(playerTeam) || playerTeam == "")
                    playerTeam = self.team;
                if (!isDefined(playerTeam) || playerTeam == "")
                    playerTeam = "axis";
                self maps\mp\gametypes\_class::giveLoadout(playerTeam, currentClass);
            }
        }
    }
}
giveAmmoOnce()
{
    refilled = 0;
    refilled = refilled + self refillWeaponAmmoDirect(self getCurrentWeapon());
    carriedWeapons = self getWeaponsListPrimaries();
    for (i = 0; i < carriedWeapons.size; i++)
        refilled = refilled + self refillWeaponAmmoDirect(carriedWeapons[i]);
    self refillEquipmentAmmoOnce();
    if (refilled > 0)
        self thread rainyShowRaisedMessage("^7Ammo refilled");
    else
        self thread rainyShowRaisedMessage("^7Equipment refilled");
}
refillWeaponAmmoDirect(weapon)
{
    if (!isDefined(weapon) || weapon == "none")
        return 0;
    self giveMaxAmmo(weapon);
    return 1;
}
refillEquipmentAmmoOnce()
{
    self setWeaponAmmoStock("frag_grenade_mp", 1);
    self setWeaponAmmoStock("semtex_mp", 1);
    self setWeaponAmmoStock("throwingknife_mp", 1);
    self setWeaponAmmoStock("claymore_mp", 1);
    self setWeaponAmmoStock("c4_mp", 1);
    self setWeaponAmmoStock("bouncingbetty_mp", 1);
    self setWeaponAmmoStock("flash_grenade_mp", 2);
    self setWeaponAmmoStock("concussion_grenade_mp", 2);
    self setWeaponAmmoStock("smoke_grenade_mp", 1);
    self setWeaponAmmoStock("trophy_mp", 1);
    self setWeaponAmmoStock("portable_radar_mp", 1);
}
giveMenuWeapon(weapon, displayName)
{
    // Track camo per-weapon so giving a NEW weapon doesn't wipe the camo index
    // that was set on a DIFFERENT weapon. rainyCamoByWeapon[name] stores each gun's
    // camo independently; rainyCamoIndex always reflects the CURRENT gun's camo.
    if (!isDefined(self.rainyCamoByWeapon))
        self.rainyCamoByWeapon = [];
    self.rainyCamoByWeapon[weapon] = 0;   // new weapon starts bare
    self.rainyCamoIndex = 0;              // current-weapon view also resets for this new gun
    self giveWeapon(weapon);
    self switchToWeapon(weapon);
    self setWeaponAmmoClip(weapon, 999);
    self setWeaponAmmoStock(weapon, 999);
    /*
        Generic per-page messages instead of a unique string per weapon (was "Gave " +
        displayName for all 58 weapons across every category). Each unique string adds
        a permanent entry to the engine's limited string table for the rest of the
        match, so collapsing 58 unique messages down to 3 reusable ones meaningfully
        cuts how fast that table fills up - the same fix already used for Attachments
        ("Attachment equipped" regardless of which attachment).

        self.menuPage is still whatever page triggered this call (giveMenuWeapon never
        navigates pages itself), so it's used both to pick the right generic message
        AND to assign this page's single fixed color. Per request, color is ONE fixed
        choice per whole page - not alternating by row - and the choices below are
        deliberately not in an alternating/predictable order.
    */
    if (self.menuPage == "lethals")
    {
        self thread rainyShowRaisedMessage("^5Lethal Given");
    }
    else if (self.menuPage == "tacticals")
    {
        self thread rainyShowRaisedMessage("^7Tactical Given");
    }
    else
    {
        pageColor = "^5";
        if (self.menuPage == "handguns")
            pageColor = "^5";
        else if (self.menuPage == "shotguns")
            pageColor = "^7";
        else if (self.menuPage == "machinepistols")
            pageColor = "^5";
        else if (self.menuPage == "assaultrifles")
            pageColor = "^7";
        else if (self.menuPage == "smgs")
            pageColor = "^7";
        else if (self.menuPage == "lmgs")
            pageColor = "^5";
        else if (self.menuPage == "specials")
            pageColor = "^5";
        else if (self.menuPage == "launchers")
            pageColor = "^7";
        // "snipers" and any unlisted page fall through to the "^5" default above.
        self thread rainyShowRaisedMessage(pageColor + "Gave Weapon");
    }
}
dropCurrentMenuWeapon()
{
    weapon = self getCurrentWeapon();
    if (!isDefined(weapon) || weapon == "none")
    {
        self thread rainyShowRaisedMessage("^7No Weapon To Drop");
        return;
    }
    feetPos = self.origin;
    item = self dropItem(weapon);
    if (isDefined(item))
        item thread pinDroppedItemToFeet(feetPos);
    rainyRecordGroundGun(feetPos, weapon, item);
    self thread rainyShowRaisedMessage("^7Dropped Current Weapon");
}
pinDroppedItemToFeet(feetPos)
{
    for (i = 0; i < 12; i++)
    {
        if (!isDefined(self))
            return;
        self.origin = feetPos;
        wait 0.05;
    }
}
giveCamoToWeapon(camoIndex)
{
    self endon("disconnect");
    weapon = self getCurrentWeapon();
    rowColor = "^7";
    if (self.menuIndex % 2 == 0)
        rowColor = "^5";
    if (!isDefined(weapon) || weapon == "none")
    {
        self thread rainyShowRaisedMessage(rowColor + "No Weapon Held");
        return;
    }
    if (!self getWeaponCanHaveCamo(weapon))
    {
        self thread rainyShowRaisedMessage(rowColor + "This weapon can't have a camo");
        return;
    }
    // Remember the camo per-weapon AND as the current index.
    if (!isDefined(self.rainyCamoByWeapon))
        self.rainyCamoByWeapon = [];
    self.rainyCamoByWeapon[weapon] = camoIndex;
    self.rainyCamoIndex = camoIndex;
    // Proven IW4x pattern (matches Synergy's equip_camo): take the weapon, switch to
    // whatever primary remains, wait one frame so the take registers, then re-give the
    // weapon with the new camo index and draw it back. The brief switch is required -
    // the engine only loads a weapon's camo when it is drawn fresh.
    self takeWeapon(weapon);
    prims = self getWeaponsListPrimaries();
    if (isDefined(prims) && prims.size > 0)
        self switchToWeapon(prims[0]);
    wait 0.05;
    self _giveWeapon(weapon, camoIndex);
    self setWeaponAmmoClip(weapon, 999);
    self setWeaponAmmoStock(weapon, 999);
    self switchToWeapon(weapon);
    if (camoIndex == 0)
        self thread rainyShowRaisedMessage(rowColor + "Camo Removed");
    else
        self thread rainyShowRaisedMessage(rowColor + "Camo Applied");
}
deleteCurrentMenuWeapon()
{
    weapon = self getCurrentWeapon();
    if (!isDefined(weapon) || weapon == "none")
    {
        self thread rainyShowRaisedMessage("^7No Weapon To Delete");
        return;
    }
    // takeWeapon removes it from the player entirely (not dropped on the ground),
    // then switch to whatever primary remains.
    self takeWeapon(weapon);
    remaining = self getWeaponsListPrimaries();
    if (isDefined(remaining) && remaining.size > 0)
        self switchToWeapon(remaining[0]);
    self thread rainyShowRaisedMessage("^7Deleted Current Weapon");
}
takeGroundWeapon()
{
    // Find the nearest tracked dropped weapon the player is standing over and add it
    // directly (giveWeapon ignores the 2-gun pickup limit). Does nothing if none near.
    if (!isDefined(level.rainyGroundGuns) || level.rainyGroundGuns.size == 0)
    {
        self thread rainyShowRaisedMessage("^5No Ground Weapon Here");
        return;
    }
    bestIdx = -1;
    bestDist = 150 * 150;
    for (i = 0; i < level.rainyGroundGuns.size; i++)
    {
        g = level.rainyGroundGuns[i];
        if (!isDefined(g) || !isDefined(g.valid) || !g.valid)
            continue;
        d = distanceSquared(self.origin, g.origin);
        if (d < bestDist)
        {
            bestDist = d;
            bestIdx = i;
        }
    }
    if (bestIdx < 0)
    {
        self thread rainyShowRaisedMessage("^5No Ground Weapon Here");
        return;
    }
    g = level.rainyGroundGuns[bestIdx];
    // Re-give with the stored camo index so the skin survives the drop/pickup cycle.
    // Dropped items only remember the base weapon name, so we re-apply camo manually.
    camoIdx = 0;
    if (isDefined(g.camoIndex))
        camoIdx = g.camoIndex;
    self _giveWeapon(g.weapon, camoIdx);
    self switchToWeapon(g.weapon);
    self setWeaponAmmoClip(g.weapon, 999);
    self setWeaponAmmoStock(g.weapon, 999);
    self.rainyCamoIndex = camoIdx;
    // Remove the world model from the ground. Both menu drops AND death-drops now
    // carry a real entity handle (death-drops are dropped by rainyControlledDeathDrop
    // while the victim is still alive), so the handle delete() path below removes the
    // model reliably.
    self removeGroundWeaponModel(g.weapon, g.ent);
    g.valid = false;
    self thread rainyShowRaisedMessage("^5Took Ground Weapon");
}
removeGroundWeaponModel(weapon, ent)
{
    // Direct handle first (weapons we dropped ourselves via the menu).
    if (isDefined(ent))
    {
        ent delete();
        return;
    }
    if (!isDefined(weapon) || weapon == "none")
        return;
    // Dropped weapon items carry the classname "weapon_<weaponname>" (see the game's
    // _weapons::getItemWeaponName), so the nearest one of this type near the player is
    // the model they are standing on.
    items = getEntArray("weapon_" + weapon, "classname");
    if (!isDefined(items) || items.size == 0)
        return;
    best = undefined;
    bestD = 200 * 200;
    for (i = 0; i < items.size; i++)
    {
        if (!isDefined(items[i]) || !isDefined(items[i].origin))
            continue;
        d = distanceSquared(self.origin, items[i].origin);
        if (d < bestD)
        {
            bestD = d;
            best = items[i];
        }
    }
    if (isDefined(best))
        best delete();
}
rainyHeldWeaponPoll()
{
    self endon("disconnect");
    level endon("game_ended");
    level endon("rainy_shutdown");
    for (;;)
    {
        if (isAlive(self))
        {
            cw = self getCurrentWeapon();
            if (isDefined(cw) && cw != "none")
                self.rainyHeldWeapon = cw;
        }
        wait 0.4;
    }
}
rainyGroundGunDeathWatch()
{
    self endon("disconnect");
    level endon("game_ended");
    level endon("rainy_shutdown");
    for (;;)
    {
        self waittill("death");
        // Gun deaths are now recorded by rainyControlledDeathDrop() inside the damage
        // hook, which drops a tracked entity we hold a handle to. Recording again here
        // would add a second, handle-less entry at the same spot whose model can't be
        // deleted - so this watcher no longer records anything itself.
    }
}
rainyRecordGroundGun(originPos, weapon, ent)
{
    if (!isDefined(level.rainyGroundGuns))
        level.rainyGroundGuns = [];
    entry = spawnStruct();
    entry.origin = originPos;
    entry.weapon = weapon;
    entry.ent = ent;
    entry.valid = true;
    // Capture the camo currently applied so pickup can restore it. Dropped item
    // entities only carry the base weapon name, so without this the camo is lost.
    if (isDefined(self) && isDefined(self.rainyCamoIndex))
        entry.camoIndex = self.rainyCamoIndex;
    else
        entry.camoIndex = 0;
    if (level.rainyGroundGuns.size >= 30)
    {
        // FIFO: shift out the oldest drop to keep the list bounded.
        for (i = 0; i < level.rainyGroundGuns.size - 1; i++)
            level.rainyGroundGuns[i] = level.rainyGroundGuns[i + 1];
        level.rainyGroundGuns[level.rainyGroundGuns.size - 1] = entry;
    }
    else
        level.rainyGroundGuns[level.rainyGroundGuns.size] = entry;
}
rainyControlledDeathDrop()
{
    // Runs inside the damage callback the instant before a fatal hit lands, while the
    // victim is still alive (so dropItem still works). Must contain NO waits - the
    // damage callback can't yield. Dropping the held weapon ourselves returns a real
    // entity handle, which Take Ground Weapon can delete() later; that is impossible
    // for engine-spawned death-drops. We then strip whatever is left so the engine's
    // own death handler has nothing to drop, leaving exactly one tracked model.
    weapon = self getCurrentWeapon();
    if (!isDefined(weapon) || weapon == "none")
        return;
    handle = self dropItem(weapon);
    if (!isDefined(handle))
        return;
    rainyRecordGroundGun(handle.origin, weapon, handle);
    rest = self getWeaponsListAll();
    if (isDefined(rest))
    {
        for (i = 0; i < rest.size; i++)
        {
            if (isDefined(rest[i]) && rest[i] != "none")
                self takeWeapon(rest[i]);
        }
    }
}
rainyResetTransientPlayerSettings(target)
{
    if (isDefined(target) && target isBot())
        return;

    // FOV, speed, super jump, third person, and the active Vision are all
    // implemented with real dvars/postfx (cg_fov / g_speed / g_gravity /
    // camera_thirdPerson / vision postfx) that live outside any single player
    // entity. A fresh entity in the next private match resets self.rainyFovLevel
    // etc. back to undefined -- so the menu shows everything at default -- but
    // the dvars/postfx themselves were never touched and carry the old values
    // straight into the next match. Call this on every "the match is ending"
    // path so the actual game state matches what the menu will show.
    if (!isDefined(target))
        target = self;

    rainyResetBotTeamDifficultyDefaults();

    // UFO state does NOT naturally reset across a match restart - self.ufoEnabled is a
    // plain player field that survives untouched, while the engine tears down the level
    // (and the script_origin self.ufoEntity was linked to) underneath it. Without this,
    // the very next spawn, ufoRespawnWatcher (see its own comment) dutifully relinks the
    // player back to that now-stale entity/position, which is exactly what was producing
    // spawns far outside the map's normal play area. Mirrors toggleUFO's own OFF-path
    // teardown sequence exactly: stop the UFO loops first, then tear down the entity/link.
    target notify("StopUFO");
    target rainyTearDownUfo();

    target notify("stopJumpBoost");
    target notify("stopInfiniteCarePackage");
    target notify("stopForgeMode");
    target.rainyInfiniteCarePackage = false;
    target.rainyForgeMode = false;
    target.gravityLevel = 1;
    setDvar("g_gravity", "800");
    target.playerSpeedLevel = 1;
    target setClientDvar("g_speed", "190");
    target.rainyFovLevel = 1;
    target setClientDvar("cg_fov", "65");
    target setClientDvar("cg_fovScale", "1.0");
    // setDvar only actually moves the needle for the host on a listen
    // server - confirmed via direct testing that setClientDvar does not
    // move cg_fov for non-host clients in this engine. Gated to the host so
    // this doesn't stomp other targets' FOV back to 65 when this runs on
    // them via the all-players reset loop.
    if (isDefined(target.rainyWasHost) && target.rainyWasHost)
        setDvar("cg_fov", "65");
    setDvar("camera_thirdPerson", "0");
    level.rainyNoPlayerCollision = false;
    setDvar("bg_playerCollision", "1");
    setDvar("bg_playerEjection", "1");
    target visionSetNakedForPlayer("", 0.1);

    // God Mode (like UFO above) is plain player state that survives a match
    // restart untouched - self.godMode would otherwise carry true into the next
    // match while the menu shows it OFF (since a fresh entity's godMode reads
    // undefined), leaving the player's actual health behavior out of sync with
    // what the UI displays. god_mode_restart kills godModeLoop via its own
    // endon (same mechanism toggleGodMode's OFF-path already uses) before the
    // health/maxhealth values are reset, so the loop can't immediately
    // re-overwrite them on its next tick.
    target notify("god_mode_restart");
    target.godMode = false;
    target.maxhealth = 100;
    target.health = 100;
}
rainyResetTransientSettingsAllPlayers()
{
    // Level-scope version for use outside a per-player thread (the F3 monitor
    // runs at level scope, not on a specific player).
    rainyResetBotTeamDifficultyDefaults();

    if (!isDefined(level.players))
        return;
    for (i = 0; i < level.players.size; i++)
    {
        if (isDefined(level.players[i]) && !level.players[i] isBot())
            rainyResetTransientPlayerSettings(level.players[i]);
    }
}
rainyCleanupOnGameEnd()
{
    self endon("disconnect");
    level waittill("game_ended");

    // Do NOT shut the Rainy HUD system down immediately on a normal final kill.
    // The stock endgame flow fires game_ended right as the final-hit damage callback
    // finishes, and the old cleanup path instantly destroyed the shot-feed HUD/queue.
    // That erased Trickshot Distance (and could erase hitmarker/almost-hit entries)
    // before the postgame scoreboard/credits had a chance to show them.
    //
    // Tear the menu and movement-style effects down now, but leave the shot feed alive
    // for a short postgame grace window so final-kill messages can be queued, rebuilt,
    // and rendered over the endgame screen. After the grace window we still perform the
    // hard cleanup that prevents stale HUD/entity state from carrying back to the lobby.
    self rainyResetTransientPlayerSettings();

    self.menuOpen = false;
    self notify("rainy_menu_closed");
    self destroyMenuHud();

    // Welcome banner isn't part of the final-kill messaging we deliberately keep
    // alive through the postgame grace window (Trickshot Distance/hitmarker/almost-hit
    // feed) - tear it down immediately rather than letting it visually linger until
    // rainyTeardownMenu(true) runs after the full grace wait below.
    self rainyTeardownWelcomeBannerHud();

    if (isDefined(self.ufoEnabled) && self.ufoEnabled)
    {
        self.ufoEnabled = false;
        self unlink();
        self enableweapons();
    }
    if (isDefined(self.ufoEntity))
    {
        self.ufoEntity delete();
        self.ufoEntity = undefined;
    }

    self rainyStartPostGameBroadcastRefresh();

    wait rainyPostGameBroadcastGraceSeconds();

    level.rainyLevelShuttingDown = true;
    level notify("rainy_shutdown");
    self rainyTeardownMenu(true);
}
rainyCleanupOnDisconnect()
{
    self waittill("disconnect");
    // Do not call setClientDvar(), visionSetNakedForPlayer(), unlink(), or HUD destroy
    // after the disconnect notify has fired. On IW4x this can fatal-error while returning
    // from a private match to the lobby/main menu.
    //
    // Important: a normal non-host player leaving should NOT broadcast rainy_shutdown.
    // That notify is level-wide and stops the host menu/broadcast loops for everyone.
    // Only the host/menu holder disconnecting (or an actual game-ending state) should
    // be treated as the whole Rainy menu system shutting down.
    if ((isDefined(self.rainyWasHost) && self.rainyWasHost) || rainyGameIsEnding())
    {
        level.rainyLevelShuttingDown = true;
        level notify("rainy_shutdown");
    }
}
rainyTeardownMenu(fullUnlink)
{
    // Destroy all menu HUD elements (and unlink/clean the UFO entity) before the
    // level tears down. Leftover client HUD elements are what crash the renderer
    // re-init when backing out of the match to the main menu.
    level.rainyLevelShuttingDown = true;
    self.menuOpen = false;
    self notify("rainy_menu_closed");
    self rainyTeardownBroadcastHud();
    self rainyTeardownMsgStackHud();
    self rainyTeardownWelcomeBannerHud();
    self destroyMenuHud();
    if (fullUnlink && isDefined(self.ufoEnabled) && self.ufoEnabled)
    {
        self.ufoEnabled = false;
        self unlink();
        self enableweapons();
    }
    if (isDefined(self.ufoEntity))
    {
        self.ufoEntity delete();
        self.ufoEntity = undefined;
    }
}
rainyTeardownBroadcastHud()
{
    self notify("rainy_broadcast_shutdown");
    self.rainyBroadcastQueueRunning = false;
    self.rainyBroadcastFadeLoopRunning = false;
    self.rainyBroadcastQueue = [];
    self.rainyShotFeedMsgs = [];
    self.rainyShotFeedTimes = [];

    if (isDefined(self.rainyBroadcastSlotHuds))
    {
        for (i = 0; i < self.rainyBroadcastSlotHuds.size; i++)
        {
            if (isDefined(self.rainyBroadcastSlotHuds[i]))
                self.rainyBroadcastSlotHuds[i] destroy();
        }
    }

    self.rainyBroadcastSlotHuds = undefined;
}
rainyReleaseBroadcastSlotsForMenu()
{
    // Destroy ONLY the feed's client-HUD slot elements (freeing their HUD-pool slots),
    // leaving the queue/message state intact. Used to hand those slots to the menu while
    // it is open. Idempotent: safe to call when the slots are already gone. The feed
    // rebuilds these the next time a message renders with the menu closed.
    if (!isDefined(self.rainyBroadcastSlotHuds))
        return;
    for (i = 0; i < self.rainyBroadcastSlotHuds.size; i++)
    {
        if (isDefined(self.rainyBroadcastSlotHuds[i]))
            self.rainyBroadcastSlotHuds[i] destroy();
    }
    self.rainyBroadcastSlotHuds = undefined;
}
getWeaponCanHaveCamo(weapon)
{
    if (!isDefined(weapon) || weapon == "none")
        return false;
    c = getWeaponClass(weapon);
    if (!isDefined(c))
        return false;
    // Secondaries / equipment can't take a weapon camo in MW2.
    if (c == "weapon_pistol" || c == "weapon_machine_pistol" || c == "weapon_projectile" || c == "weapon_grenade" || c == "weapon_turret" || c == "weapon_melee")
        return false;
    return true;
}
loadCamoList()
{
    self.camo0 = undefined; self.camoIdx0 = undefined;
    self.camo1 = undefined; self.camoIdx1 = undefined;
    self.camo2 = undefined; self.camoIdx2 = undefined;
    self.camo3 = undefined; self.camoIdx3 = undefined;
    self.camo4 = undefined; self.camoIdx4 = undefined;
    self.camo5 = undefined; self.camoIdx5 = undefined;
    self.camo6 = undefined; self.camoIdx6 = undefined;
    self.camo7 = undefined; self.camoIdx7 = undefined;
    self.camo8 = undefined; self.camoIdx8 = undefined;
    self.camo9 = undefined; self.camoIdx9 = undefined;

    // Index 0 is the engine's default bare/no-camo look. Keep it at the very top
    // of the Give Camo menu so players can remove a camo from the current weapon
    // through the exact same re-give path used by the normal camo entries.
    self.camo0 = "None";
    self.camoIdx0 = 0;

    // Read the engine's own camo table so the displayed name and the applied camo
    // index always come from the SAME row - they can never mismatch (col 0 = index
    // passed to giveWeapon, col 1 = camo name), exactly how the game applies camo.
    count = 1;
    for (row = 0; row < 40; row++)
    {
        if (count >= 10)
            break;
        idxStr = tableLookupByRow("mp/camoTable.csv", row, 0);
        if (!isDefined(idxStr) || idxStr == "")
            break;
        idx = int(idxStr);
        // Only camo indices 1-8 actually render on weapons in IW4x (index 0 is the
        // default no-camo look; gold and any other higher entries are leftover table
        // rows that don't apply to weapons). The Synergy menu uses this exact 1-8 range
        // for its working camo equip, so we mirror it - this is what drops the bogus
        // "gold" entry.
        if (idx < 1 || idx > 8)
            continue;
        nameStr = tableLookupByRow("mp/camoTable.csv", row, 1);
        display = camoDisplayName(nameStr, count);
        // Belt-and-suspenders: also skip anything named gold, in case a future table
        // places a non-rendering gold row inside the 1-8 range.
        if (rainyIsGoldCamo(nameStr) || rainyIsGoldCamo(display))
            continue;
        if (count == 0) { self.camo0 = display; self.camoIdx0 = idx; }
        else if (count == 1) { self.camo1 = display; self.camoIdx1 = idx; }
        else if (count == 2) { self.camo2 = display; self.camoIdx2 = idx; }
        else if (count == 3) { self.camo3 = display; self.camoIdx3 = idx; }
        else if (count == 4) { self.camo4 = display; self.camoIdx4 = idx; }
        else if (count == 5) { self.camo5 = display; self.camoIdx5 = idx; }
        else if (count == 6) { self.camo6 = display; self.camoIdx6 = idx; }
        else if (count == 7) { self.camo7 = display; self.camoIdx7 = idx; }
        else if (count == 8) { self.camo8 = display; self.camoIdx8 = idx; }
        else if (count == 9) { self.camo9 = display; self.camoIdx9 = idx; }
        count++;
    }
    self.camoCount = count;
}
rainyIsGoldCamo(s)
{
    if (!isDefined(s))
        return false;
    return (isSubStr(s, "gold") || isSubStr(s, "Gold") || isSubStr(s, "GOLD"));
}
camoDisplayName(raw, fallbackIdx)
{
    // Hardcode the 8 renderable MW2 camo names (indices 1-8) directly.
    // This avoids all string-slicing functions that don't exist in IW4x GSC.
    if (!isDefined(raw) || raw == "")
        return "Camo " + fallbackIdx;
    if (raw == "camo_woodland" || raw == "woodland") return "Woodland";
    if (raw == "camo_desert"   || raw == "desert")   return "Desert";
    if (raw == "camo_arctic"   || raw == "arctic")   return "Arctic";
    if (raw == "camo_digital"  || raw == "digital")  return "Digital";
    if (raw == "camo_redurban" || raw == "redurban" || raw == "camo_red_urban" || raw == "red_urban") return "Red Urban";
    if (raw == "camo_redtiger" || raw == "redtiger" || raw == "camo_red_tiger" || raw == "red_tiger") return "Red Tiger";
    if (raw == "camo_bluetiger"|| raw == "bluetiger" || raw == "camo_blue_tiger"|| raw == "blue_tiger") return "Blue Tiger";
    if (raw == "camo_orangefall"||raw == "orangefall"||raw == "camo_orange_fall"||raw == "orange_fall") return "Orange Fall";
    // Fallback: return the raw name as-is (already readable enough).
    return raw;
}
rainyUpperFirst(w)
{
    // Stub - no longer called. camoDisplayName now uses hardcoded names.
    return w;
}
toggleGodMode()
{
    if (!isDefined(self.godMode))
        self.godMode = false;
    self.godMode = !self.godMode;
    if (self.godMode)
    {
        self.maxhealth = 999999;
        self.health = 999999;
        self notify("god_mode_restart");
        self thread godModeLoop();
        self thread rainyShowRaisedMessage("^5God Mode ^7[^5ON^7]");
    }
    else
    {
        self notify("god_mode_restart");
        self.maxhealth = 100;
        self.health = 100;
        self thread rainyShowRaisedMessage("^5God Mode ^7[^5OFF^7]");
    }
}
godModeLoop()
{
    self endon("disconnect");
    self endon("god_mode_restart");
    level endon("game_ended");
    level endon("rainy_shutdown");
    while (isDefined(self.godMode) && self.godMode)
    {
        self.maxhealth = 999999;
        self.health = 999999;
        wait 0.05;
    }
}
addBotsAmount(amount)
{
    current = getDvarInt("bots_manage_add");
    setDvar("bots_manage_add", current + amount);
    // Each amount value maps to exactly one addbots row (see the addbots HUD
    // render block): 1->row0(cyan), 3->row1(white), 7->row2(cyan), 11->row3(white),
    // 17->row4(cyan). Branch on amount to match each call site's own row color.
    if (amount == 1)
        self thread rainyShowRaisedMessage("^5Adding 1 Bot");
    else if (amount == 3)
        self thread rainyShowRaisedMessage("^7Adding 3 Bots");
    else if (amount == 7)
        self thread rainyShowRaisedMessage("^5Adding 7 Bots");
    else if (amount == 11)
        self thread rainyShowRaisedMessage("^7Adding 11 Bots");
    else if (amount == 17)
        self thread rainyShowRaisedMessage("^5Adding 17 Bots");
    else
        self thread rainyShowRaisedMessage("^5Adding " + amount + " Bots");
}
kickAllBots()
{
    bots = getBotArray();
    if (!isDefined(bots) || bots.size <= 0)
    {
        self thread rainyShowRaisedMessage("^7No Bots To Kick");
        return;
    }
    count = bots.size;
    for (i = 0; i < bots.size; i++)
    {
        bot = bots[i];
        if (isDefined(bot))
        {
            kick(bot getEntityNumber(), "EXE_PLAYERKICKED");
            wait 0.05;
        }
    }
    self thread rainyShowRaisedMessage("^7Kicked All Bots");
}
killAllBots()
{
    bots = getBotArray();
    if (!isDefined(bots) || bots.size <= 0)
    {
        self thread rainyShowRaisedMessage("^5No Bots To Kill");
        return;
    }
    for (i = 0; i < bots.size; i++)
    {
        bot = bots[i];
        if (isDefined(bot) && isAlive(bot))
        {
            bot suicide();
        }
    }
    self thread rainyShowRaisedMessage("^5Killed All Bots");
}
rainyBotIgnoresGlobalFreeze(bot)
{
    if (!isDefined(bot))
        return false;
    if (isDefined(bot.rainyIgnoreGlobalBotFreeze) && bot.rainyIgnoreGlobalBotFreeze)
        return true;
    return false;
}
rainyBotShouldStayPinned(bot)
{
    if (!isDefined(bot))
        return false;
    if (isDefined(bot.rainyFrozen) && bot.rainyFrozen)
        return true;
    if (isDefined(level.botsFrozen) && level.botsFrozen)
    {
        if (!rainyBotIgnoresGlobalFreeze(bot))
            return true;
    }
    return false;
}
rainyClearBotGlobalFreezeOverride(bot)
{
    if (!isDefined(bot))
        return;
    if (!bot isBot())
        return;
    bot.rainyIgnoreGlobalBotFreeze = undefined;
}
rainyResetBotPath(bot)
{
    if (!isDefined(bot))
        return;
    bot notify("kill_goal");
    if (isDefined(bot.bot))
    {
        bot.bot.next_wp = -1;
        bot.bot.second_next_wp = -1;
        bot.bot.last_next_wp = -1;
        bot.bot.last_second_next_wp = -1;
    }
}
rainyClearGlobalBotFreezePins(clearIndividualPins)
{
    if (!isDefined(level.players))
        return;
    for (i = 0; i < level.players.size; i++)
    {
        bot = level.players[i];
        if (!isDefined(bot) || !bot isBot())
            continue;
        bot.rainyIgnoreGlobalBotFreeze = undefined;
        if (!clearIndividualPins && isDefined(bot.rainyFrozen) && bot.rainyFrozen)
            continue;
        bot.frozenOrigin = undefined;
        bot.frozenAngles = undefined;
        if (clearIndividualPins)
        {
            bot.rainyFrozen = false;
            bot notify("rainy_unfreeze");
            bot.rainyFrozenOrigin = undefined;
            bot.rainyFrozenAngles = undefined;
        }
        bot SetVelocity((0, 0, 0));
        bot freezeControls(false);
        rainyResetBotPath(bot);
    }
}
toggleFreezeBots()
{
    currentFrozen = false;
    if (isDefined(level.botsFrozen) && level.botsFrozen)
        currentFrozen = true;

    // Freeze/Unfreeze Bots is the master bot movement toggle. Whichever way it is
    // selected, it should override older All Players / individual bot freeze
    // states so the newest menu action wins cleanly for bots.
    if (!currentFrozen)
    {
        level.botsFrozen = true;
        level.softStackFreeze = false;
        setDvar("bots_play_move", "0");

        // Clear old individual bot pins/exceptions first, then apply the new
        // global bot freeze. This prevents stale per-bot state from fighting
        // the new Frozen selection.
        rainyClearGlobalBotFreezePins(true);
        self freezeBotsInPlace();
        level thread freezeBotsLoop();
        self thread rainyShowRaisedMessage("^7Bots Frozen");
    }
    else
    {
        level.botsFrozen = false;
        level.softStackFreeze = false;
        setDvar("bots_play_move", "1");

        // Clear global pins AND individual bot freezes. This lets the Unfrozen
        // selection override a previous All Players > Freeze All or any older
        // individual bot freeze state.
        rainyClearGlobalBotFreezePins(true);
        self thread rainyShowRaisedMessage("^7Bots Unfrozen");
    }
}
freezeBotsInPlace()
{
    if (!isDefined(level.players))
        return;
    level.softStackFreeze = false;
    for (i = 0; i < level.players.size; i++)
    {
        bot = level.players[i];
        if (isDefined(bot) && bot isBot())
        {
            if (rainyBotIgnoresGlobalFreeze(bot))
                continue;
            bot SetVelocity((0, 0, 0));
            bot.frozenOrigin = bot.origin;
            bot.frozenAngles = bot.angles;
        }
    }
}
bringBotsToCrosshair()
{
    self endon("disconnect");
    if (!isDefined(level.players))
    {
        self thread rainyShowRaisedMessage("^7No players found");
        return;
    }
    // Find where the crosshair points: trace from the head along the view angles.
    eyePos = self getTagOrigin("j_head");
    forward = anglesToForward(self GetPlayerAngles());
    trace = bulletTrace(eyePos, eyePos + (forward * 1000000), false, self);
    if (isDefined(trace["fraction"]) && trace["fraction"] >= 1.0)
        center = self.origin + (forward * 256);   // aiming at open sky: use a point ahead
    else
        center = trace["position"] - (forward * 16); // sit just off the hit surface, not inside it
    count = 0;
    for (i = 0; i < level.players.size; i++)
    {
        bot = level.players[i];
        if (isDefined(bot) && bot isBot())
        {
            // Tight ring around the crosshair point, ground-traced, so bots land on
            // valid floor and (with distinct origins) can disperse out of the cluster.
            ang = randomint(360);
            rad = randomintrange(12, 44);
            spot = center + (cos(ang) * rad, sin(ang) * rad, 0);
            ground = physicstrace(spot + (0, 0, 72), spot + (0, 0, -160), false, bot);
            if (isDefined(ground))
                spot = ground + (0, 0, 2);
            bot SetVelocity((0, 0, 0));
            bot SetOrigin(spot);
            bot SetPlayerAngles(self.angles);
            if (rainyBotShouldStayPinned(bot))
            {
                bot.frozenOrigin = spot;
                bot.frozenAngles = self.angles;
                if (isDefined(bot.rainyFrozen) && bot.rainyFrozen)
                {
                    bot.rainyFrozenOrigin = spot;
                    bot.rainyFrozenAngles = self.angles;
                }
            }
            else
            {
                bot notify("kill_goal");
                if (isDefined(bot.bot))
                {
                    bot.bot.next_wp = -1;
                    bot.bot.second_next_wp = -1;
                    bot.bot.last_next_wp = -1;
                    bot.bot.last_second_next_wp = -1;
                }
            }
            count++;
        }
    }
    self thread rainyShowRaisedMessage("^7Teleported Bots To Crosshair");
}
bringBotsToPlayer()
{
    self endon("disconnect");
    if (!isDefined(level.players))
    {
        self thread rainyShowRaisedMessage("^5No players found");
        return;
    }
    count = 0;
    center = self.origin;
    for (i = 0; i < level.players.size; i++)
    {
        bot = level.players[i];
        if (isDefined(bot) && bot isBot())
        {
            // Spread bots across a tight ring instead of one identical point. When every
            // bot shares the exact same origin their pathfinding goes degenerate and the
            // pile can't separate; distinct, ground-traced origins let them disperse.
            ang = randomint(360);
            rad = randomintrange(12, 44);
            spot = center + (cos(ang) * rad, sin(ang) * rad, 0);
            ground = physicstrace(spot + (0, 0, 48), spot + (0, 0, -80), false, bot);
            if (isDefined(ground))
                spot = ground + (0, 0, 2);
            bot SetVelocity((0, 0, 0));
            bot SetOrigin(spot);
            bot SetPlayerAngles(self.angles);
            if (rainyBotShouldStayPinned(bot))
            {
                bot.frozenOrigin = spot;
                bot.frozenAngles = self.angles;
                if (isDefined(bot.rainyFrozen) && bot.rainyFrozen)
                {
                    bot.rainyFrozenOrigin = spot;
                    bot.rainyFrozenAngles = self.angles;
                }
            }
            else
            {
                // Drop any stale pre-teleport path so the bot re-routes from its new spot.
                bot notify("kill_goal");
                if (isDefined(bot.bot))
                {
                    bot.bot.next_wp = -1;
                    bot.bot.second_next_wp = -1;
                    bot.bot.last_next_wp = -1;
                    bot.bot.last_second_next_wp = -1;
                }
            }
            count++;
        }
    }
    self thread rainyShowRaisedMessage("^5Teleported Bots To You");
}
freezeBotsLoop()
{
    level endon("game_ended");
    level endon("rainy_shutdown");
    if (isDefined(level.freezeBotsLoopRunning) && level.freezeBotsLoopRunning)
        return;
    level.freezeBotsLoopRunning = true;
    while (isDefined(level.botsFrozen) && level.botsFrozen)
    {
        if (isDefined(level.players))
        {
            for (i = 0; i < level.players.size; i++)
            {
                bot = level.players[i];
                if (isDefined(bot) && bot isBot())
                {
                    if (rainyBotIgnoresGlobalFreeze(bot) && (!isDefined(bot.rainyFrozen) || !bot.rainyFrozen))
                    {
                        bot.frozenOrigin = undefined;
                        bot.frozenAngles = undefined;
                        continue;
                    }
                    if (!isDefined(bot.frozenOrigin))
                        bot.frozenOrigin = bot.origin;
                    if (!isDefined(bot.frozenAngles))
                        bot.frozenAngles = bot.angles;
                    bot SetVelocity((0, 0, 0));
                    bot SetOrigin(bot.frozenOrigin);
                    bot SetPlayerAngles(bot.frozenAngles);
                }
            }
        }
        wait 0.05;
    }
    level.freezeBotsLoopRunning = false;
}
rainyFreezeEntity(target)
{
    // Freeze a single player or bot in place. Works for both - stores the lock
    // position on the entity and runs a per-entity pin loop. Host is never frozen.
    if (!isDefined(target))
        return;
    if (target isHost())
        return;
    target.rainyFrozen = true;
    target.rainyFrozenOrigin = target.origin;
    target.rainyFrozenAngles = target.angles;
    target SetVelocity((0, 0, 0));
    // Bots also use the bot-warfare frozen flag so their AI goal loop stops.
    if (target isBot())
    {
        target.rainyIgnoreGlobalBotFreeze = undefined;
        target.frozenOrigin = target.origin;
        target.frozenAngles = target.angles;
    }
    target freezeControls(true);
    target thread rainyFreezeEntityLoop();
}
rainyFreezeEntityLoop()
{
    self endon("disconnect");
    self endon("rainy_unfreeze");
    level endon("game_ended");
    level endon("rainy_shutdown");
    while (isDefined(self.rainyFrozen) && self.rainyFrozen)
    {
        if (!isDefined(self))
            return;
        self SetVelocity((0, 0, 0));
        if (isDefined(self.rainyFrozenOrigin))
            self SetOrigin(self.rainyFrozenOrigin);
        if (isDefined(self.rainyFrozenAngles))
            self SetPlayerAngles(self.rainyFrozenAngles);
        wait 0.05;
    }
}
rainyUnfreezeEntity(target)
{
    if (!isDefined(target))
        return;
    target.rainyFrozen = false;
    target notify("rainy_unfreeze");
    target.rainyFrozenOrigin = undefined;
    target.rainyFrozenAngles = undefined;
    if (target isBot())
    {
        target.frozenOrigin = undefined;
        target.frozenAngles = undefined;
        if (isDefined(level.botsFrozen) && level.botsFrozen)
        {
            // Global bot freeze is still active. Let this one bot move while the
            // global freeze loop continues pinning every other bot.
            target.rainyIgnoreGlobalBotFreeze = true;
            setDvar("bots_play_move", "1");
            rainyResetBotPath(target);
        }
        else
        {
            target.rainyIgnoreGlobalBotFreeze = undefined;
            rainyResetBotPath(target);
        }
    }
    target SetVelocity((0, 0, 0));
    target freezeControls(false);
}
rainyKillAllPlayers()
{
    if (!isDefined(level.players))
    {
        self thread rainyShowRaisedMessage("^5No players found");
        return;
    }
    count = 0;
    for (i = 0; i < level.players.size; i++)
    {
        p = level.players[i];
        if (!isDefined(p)) continue;
        if (p isHost()) continue;     // never kill the host
        if (isAlive(p))
            p suicide();
        count++;
    }
    self thread rainyShowRaisedMessage("^5Killed " + count + " players");
}
rainyFreezeAllPlayers()
{
    if (!isDefined(level.players))
    {
        self thread rainyShowRaisedMessage("^7No players found");
        return;
    }
    level.botsFrozen = true;
    level.softStackFreeze = false;
    setDvar("bots_play_move", "0");
    rainyClearGlobalBotFreezePins(false);
    self freezeBotsInPlace();
    level thread freezeBotsLoop();
    count = 0;
    for (i = 0; i < level.players.size; i++)
    {
        p = level.players[i];
        if (!isDefined(p)) continue;
        if (p isHost()) continue;     // never freeze the host
        rainyFreezeEntity(p);
        count++;
    }
    self thread rainyShowRaisedMessage("^7Froze " + count + " players");
}
rainyUnfreezeAllPlayers()
{
    if (!isDefined(level.players))
    {
        self thread rainyShowRaisedMessage("^5No players found");
        return;
    }
    level.botsFrozen = false;
    level.softStackFreeze = false;
    setDvar("bots_play_move", "1");
    count = 0;
    for (i = 0; i < level.players.size; i++)
    {
        p = level.players[i];
        if (!isDefined(p)) continue;
        if (p isHost()) continue;
        rainyUnfreezeEntity(p);
        count++;
    }
    rainyClearGlobalBotFreezePins(true);
    self thread rainyShowRaisedMessage("^5Unfroze " + count + " players");
}
rainyKickAllPlayers()
{
    if (!isDefined(level.players))
    {
        self thread rainyShowRaisedMessage("^7No players found");
        return;
    }
    // Build a list of targets first (kicking mutates level.players mid-loop).
    targets = [];
    for (i = 0; i < level.players.size; i++)
    {
        p = level.players[i];
        if (!isDefined(p)) continue;
        if (p isHost()) continue;     // never kick the host
        targets[targets.size] = p getEntityNumber();
    }
    count = 0;
    for (i = 0; i < targets.size; i++)
    {
        kick(targets[i], "EXE_PLAYERKICKED");
        count++;
    }
    self thread rainyShowRaisedMessage("^7Kicked " + count + " players");
}
isBot()
{
    if (isDefined(self.pers) && isDefined(self.pers["isBot"]) && self.pers["isBot"])
        return true;
    return false;
}
removeDeathBarriers()
{
    level.deathBarriersRemoved = true;
    setDvar("bg_disableBarrierClips", "0");
    level.player_out_of_playable_area_monitor = false;
    level notify("stop_player_out_of_playable_area_monitor");
    hurtTriggers = getEntArray("trigger_hurt", "classname");
    if (isDefined(hurtTriggers) && hurtTriggers.size > 0)
    {
        for (i = 0; i < hurtTriggers.size; i++)
        {
            if (isDefined(hurtTriggers[i]))
                hurtTriggers[i] delete();
        }
    }
    replaceFunc(maps\mp\_utility::_suicide, ::barrierSuicideBlock);
    setPassiveBots(true);
    setDvar("bots_main_chat", "0");
    level thread botFallRescueMonitor();
}
botFallRescueMonitor()
{
    level endon("game_ended");
    level endon("rainy_shutdown");
    while (!isDefined(level.waypoints) || level.waypoints.size <= 0)
        wait 1;
    minZ = level.waypoints[0].origin[2];
    for (i = 1; i < level.waypoints.size; i++)
    {
        if (level.waypoints[i].origin[2] < minZ)
            minZ = level.waypoints[i].origin[2];
    }
    fallThreshold = minZ - 200;
    for (;;)
    {
        wait 1;
        if (!isDefined(level.players))
            continue;
        for (i = 0; i < level.players.size; i++)
        {
            bot = level.players[i];
            if (!isDefined(bot) || !bot isBot() || !isAlive(bot))
                continue;
            if (bot.origin[2] >= fallThreshold)
                continue;
            wp = level.waypoints[randomInt(level.waypoints.size)];
            if (!isDefined(wp) || !isDefined(wp.origin))
                continue;
            bot SetVelocity((0, 0, 0));
            bot SetOrigin(wp.origin + (0, 0, 16));
            if (isDefined(bot.frozenOrigin))
                bot.frozenOrigin = undefined;
            if (isDefined(bot.frozenAngles))
                bot.frozenAngles = undefined;
        }
    }
}
barrierSuicideBlock()
{
}
noFallDamage()
{
    self endon("disconnect");
    level endon("game_ended");
    level endon("rainy_shutdown");
    for (;;)
    {
        setDvar("bg_fallDamageMinHeight", "999999");
        setDvar("bg_fallDamageMaxHeight", "999999");
        wait 1;
    }
}
rainyNightVisionDisableManager()
{
    // Lobby-wide night-vision-effect disable, applied like no-fall-damage and the
    // death-barrier removal: it covers EVERY player, not just the host. The original
    // single server-side setDvar did not reliably reach each client, so this pushes the
    // dvar to every player individually and re-applies it after each (re)spawn. Bots are
    // skipped - they have no client to render the effect.
    level endon("game_ended");
    level endon("rainy_shutdown");
    for (;;)
    {
        if (isDefined(level.rainyLevelShuttingDown) && level.rainyLevelShuttingDown)
            return;
        if (isDefined(level.players))
        {
            for (i = 0; i < level.players.size; i++)
            {
                p = level.players[i];
                if (isDefined(p) && !rainyIsBot(p) && !isDefined(p.rainyNvgDisableStarted))
                {
                    p.rainyNvgDisableStarted = true;
                    p thread rainyNightVisionDisableForPlayer();
                }
            }
        }
        wait 0.5;
    }
}
rainyNightVisionDisableForPlayer()
{
    self endon("disconnect");
    level endon("game_ended");
    level endon("rainy_shutdown");
    for (;;)
    {
        // Guard the setClientDvar: calling it as the level tears down / a client is
        // disconnecting fatal-errors on IW4x when returning to the main menu (the same
        // class of crash the disconnect-cleanup comment warns about). Only push the dvar
        // when the level is live and this client is actually a spawned, valid player.
        if ((!isDefined(level.rainyLevelShuttingDown) || !level.rainyLevelShuttingDown) && isAlive(self))
            self setClientDvar("nightVisionDisableEffects", "1");
        // Re-apply after every spawn since client dvars can be reset by the engine on
        // the respawn/loadout sequence.
        self waittill("spawned_player");
    }
}
rainyToggleEffectsRespawnWatcher()
{
    // Several toggle-effect loops intentionally stop on death via endon("death")
    // (auto refill, the aimbots, wallbang snap, super jump). Without re-arming them, the
    // effect stays dead after respawn until the host manually toggles it off and back on.
    // This re-threads each loop on every respawn IF its toggle flag is still ON, so
    // toggled effects keep working across deaths and only ever stop when actually toggled
    // OFF. Runs for every player so host-applied per-player toggles also survive that
    // player's own deaths.
    self endon("disconnect");
    level endon("game_ended");
    level endon("rainy_shutdown");
    for (;;)
    {
        self waittill("spawned_player");
        if (isDefined(self.rainyAutoRefillAmmo) && self.rainyAutoRefillAmmo)
        {
            self notify("stopAutoRefillAmmo");
            self rainyAutoRefillTick();
            self thread rainyAutoRefillAmmoLoop();
        }
        if (isDefined(self.rainyInfiniteCarePackage) && self.rainyInfiniteCarePackage)
        {
            self notify("stopInfiniteCarePackage");
            self rainyGiveCarePackageOnce();
            self thread rainyInfiniteCarePackageLoop();
        }
        if (isDefined(self.rainyForgeMode) && self.rainyForgeMode)
        {
            self notify("stopForgeMode");
            self thread rainyForgeModeLoop();
        }
        if (isDefined(self.tsAimbotOn) && self.tsAimbotOn)
        {
            self notify("stopTsAimbot");
            self thread tsAimbotLoop();
        }
        if (isDefined(self.unfairAimbotOn) && self.unfairAimbotOn)
        {
            self notify("stopUnfairAimbot");
            self thread unfairAimbotLoop();
        }
        if (isDefined(self.silentAimOn) && self.silentAimOn)
        {
            self notify("stopSilentAim");
            self thread silentAimLoop();
        }
        if (isDefined(self.snapAimOn) && self.snapAimOn)
        {
            self notify("stopSnapAim");
            self thread snapAimLoop();
        }
        if (isDefined(self.wallbangSnapOn) && self.wallbangSnapOn)
        {
            self rainyRefreshWallbangDvars();
            self notify("stopWallbangSnap");
            self thread wallbangSnapLoop();
        }
        if (isDefined(self.gravityLevel) && self.gravityLevel > 1)
        {
            self notify("stopJumpBoost");
            self thread jumpBoostLoop();
        }
    }
}
rainyMenuCloseOnDeath()
{
    // Fixes the "parts vanish, others remain (half-drawn)" menu glitch on death without
    // forcing the menu back open afterward. Root cause of the glitch: MW2/IW4x has a hard
    // client HUD-element cap. When you die the engine spawns its own killcam / "press F to
    // respawn" / killed-by HUD; if the menu's elements are still allocated, the engine's
    // death HUD pass half-clears them (some rows vanish, some remain).
    //
    // So we simply tear the menu fully down on death (freeing its slots and hiding it
    // cleanly during the killcam). We do NOT auto-reopen on respawn - the host reopens it
    // themselves with ADS+Melee whenever they want, and that fresh open rebuilds every
    // element (skull included) against a fully-free HUD pool. Only threaded for the host,
    // since only the host can open the menu.
    self endon("disconnect");
    level endon("game_ended");
    level endon("rainy_shutdown");
    for (;;)
    {
        self waittill("death");
        if (isDefined(self.menuOpen) && self.menuOpen)
            self closeMenuHud();
    }
}
rainyGameIsEnding()
{
    // Any of these means the base game is moving into the end-of-round/end-of-match
    // flow, where controls should stay locked for the scoreboard/final killcam setup.
    if (isDefined(level.gameEnded) && level.gameEnded)
        return true;
    if (isDefined(game["state"]) && game["state"] != "playing")
        return true;
    return false;
}

allowPlayerMovementAtMatchStart()
{
    // The old version called freezeControls(false) forever. That fixed prematch
    // countdown movement, but it also fought the base game's endgame freeze and let
    // the host keep moving while the scoreboard/final-killcam transition started.
    // Keep this only active until the stock prematch flag is done, then stop touching
    // controls for the rest of the match.
    self endon("disconnect");
    level endon("game_ended");
    level endon("rainy_shutdown");
    for (;;)
    {
        if (rainyGameIsEnding())
            return;
        if (gameFlag("prematch_done"))
            return;
        self freezeControls(false);
        wait 0.10;
    }
}

rainyConfigStringBudget()
{
    // The engine hard-crashes with "G_FindConfigstringIndex: overflow (511)" once the
    // level's shared string table fills. Every UNIQUE string ever passed to setText()
    // permanently reserves one slot for the whole map (slots are never freed until the
    // map changes); identical strings reuse their existing slot for free. We stop minting
    // brand-new strings short of the ceiling so a setText() call can never be the one that
    // overflows the table. 480 leaves headroom for base-game strings in the same table.
    // The level's string table resets every map change, so this budget refreshes per map.
    // NOTE: 511 is the stock-engine ceiling; IW4x has at some point raised the real
    // configstring limit above that on top of the base game, but the exact number for this
    // build (r5046) hasn't been confirmed yet. 480 is deliberately conservative against the
    // stock figure so it's safe either way - raise this only after confirming the real
    // ceiling for this build (e.g. by deliberately lowering it in a test and reading the
    // index the engine reports at the moment of overflow).
    return 480;
}
rainyGuardConfigString(text)
{
    // Returns the text while we have headroom, or "" (a string that is effectively always
    // already registered, so it costs no new slot) once we approach the ceiling. Worst case
    // after the ceiling is reached: a brand-new, never-before-seen line renders blank for the
    // rest of that map instead of HARD-CRASHING the game. Lines that were already shown once
    // keep working (they reuse their slot). This is what makes the overflow crash impossible.
    if (!isDefined(text) || text == "")
        return text;

    if (!isDefined(level.rainyCfgSeen))
    {
        level.rainyCfgSeen = [];
        level.rainyCfgCount = 0;
    }

    // Already registered this map -> reuses the existing slot, always safe.
    if (isDefined(level.rainyCfgSeen[text]))
        return text;

    // Brand-new string: register it only while we still have comfortable headroom.
    if (level.rainyCfgCount < rainyConfigStringBudget())
    {
        level.rainyCfgSeen[text] = true;
        level.rainyCfgCount++;
        return text;
    }

    // Out of headroom: do NOT create a new configstring this map.
    return "";
}
rainyIsDigit(ch)
{
    return (ch == "0" || ch == "1" || ch == "2" || ch == "3" || ch == "4" ||
            ch == "5" || ch == "6" || ch == "7" || ch == "8" || ch == "9");
}
rainyHasColorCode(s)
{
    if (!isDefined(s))
        return false;
    n = s.size;
    for (i = 0; i + 1 < n; i++)
    {
        if (getSubStr(s, i, i + 1) == "^" && rainyIsDigit(getSubStr(s, i + 1, i + 2)))
            return true;
    }
    return false;
}
rainyMenuColorFromCode(code)
{
    // CoD inline color codes -> RGB. Used to carry a stripped row's color on the
    // element (only white/non-cyan are stripped; cyan keeps its inline code).
    if (code == "^0") return (0.0, 0.0, 0.0);
    if (code == "^1") return (1.0, 0.0, 0.0);
    if (code == "^2") return (0.0, 1.0, 0.0);
    if (code == "^3") return (1.0, 1.0, 0.0);
    if (code == "^4") return (0.0, 0.0, 1.0);
    if (code == "^5") return (0.0, 1.0, 1.0);
    if (code == "^6") return (1.0, 0.0, 1.0);
    return (1.0, 1.0, 1.0);   // ^7 and anything else -> white
}
rainyCollapseRowColor(text)
{
    /*
        Configstring saver (hybrid - keeps the gold selected highlight).

        Rows are drawn as two variants of the same label:
            unselected: "^N" + "  " + label   (^5 cyan / ^7 white stripe)
            selected:   "   " + label          (no code -> element color shows)
        Two variants = two engine strings, and the 511-slot table overflows once
        enough are shown. Earlier builds collapsed by stripping ALL codes onto the
        element color, but IW4x renders element-colored CYAN a dull teal (gold and
        white render fine). So we split it:

          - CYAN rows keep their inline "^5  X" (true cyan, no teal). Their selected
            variant strips to the shared "  X" shown gold by the highlight loop, so a
            cyan label costs 2 strings (coded + gold).
          - WHITE rows strip to "  X" and carry white on the element; the selected
            gold variant is the SAME "  X" string, so a white label costs 1.
          - The no-code SELECTED variant of any row -> "  X", shown gold by the
            highlight loop (selectedColor on the hovered row).

        Net result: every selected row highlights gold, cyan stays true cyan, and the
        table stays well under the ceiling. Inline-coded bodies (toggles, title) are
        left as-is. */
    if (!isDefined(text) || text == "")
    {
        // Blanked row (unused slot on a shorter page). Clear the flag defensively so
        // a stale self-colored marker from this element's previous page can never
        // leak forward; the pulse loop is then free to manage this element's color
        // again once it's reused.
        self.rainySelfColored = false;
        return text;
    }

    n = text.size;
    i = 0;
    while (i < n && getSubStr(text, i, i + 1) == " ")
        i++;
    leadSpacesBefore = i;

    leadCode = "";
    if (i + 1 < n && getSubStr(text, i, i + 1) == "^" && rainyIsDigit(getSubStr(text, i + 1, i + 2)))
    {
        leadCode = getSubStr(text, i, i + 2);
        i += 2;
    }
    spacesAfterCode = 0;
    while (i < n && getSubStr(text, i, i + 1) == " ")
    {
        i++;
        spacesAfterCode++;
    }
    core = getSubStr(text, i, n);

    if (leadCode != "" && leadSpacesBefore == 0 && spacesAfterCode >= 2 && !rainyHasColorCode(core))
    {
        self.rainyRowColor = rainyMenuColorFromCode(leadCode);
        if (leadCode == "^5")
        {
            // Cyan must render via inline ^5 (element-color cyan looks teal), so the
            // RETURNED TEXT still carries that ^5 code. Mark self-colored so the pulse
            // loop never repaints this element gold/stripe later - if it did, the ^5
            // would tint against that color instead of rendering true cyan the moment
            // the row is deselected or pulses while idle.
            self.rainySelfColored = true;
            self.color = self.rainyRowColor;
            return text;
        }
        // White (and any non-cyan code) renders correctly via element color, so strip
        // to the shared "  X" string that the gold selected variant also uses. This
        // returned text has NO embedded code, so it's safe for the pulse loop to
        // repaint this element's color each tick - clear the flag.
        self.rainySelfColored = false;
        self.color = self.rainyRowColor;
        return "  " + core;
    }

    if (leadCode == "" && leadSpacesBefore >= 3 && core != "" && !rainyHasColorCode(core))
    {
        // Selected variant of any row -> shared "  X" with NO embedded code, shown
        // gold. Safe for the pulse loop to keep repainting - clear the flag.
        // (rainyRowColor is left untouched so the row returns to its stripe color
        // when deselected.)
        self.rainySelfColored = false;
        self.color = (1.0, 0.82, 0.0);
        return "  " + core;
    }

    // Inline-coded bodies (toggle brackets, etc.) and anything else not matching the
    // simple-row pattern: render the text exactly as authored. CRITICAL: force the
    // element to pure white first. IW4x tints inline ^N codes against the element's
    // OWN .color rather than fully overriding it, so a shared element left at any
    // non-white color (cyan/gold from a previous set_text on this same row) skews
    // every inline-coded bracket toward that color - this is what produced the teal
    // "[Normal]" bracket. Pure white makes inline codes render at their true color.
    //
    // ALSO mark the row as self-colored. updatePrestigeSelectorSpin() repaints every
    // row's .color on a ~30ms timer for as long as the menu is open (the select-bar
    // pulse), completely independent of set_text. Without this flag it would force
    // this element back to gold/stripe color moments after set_text runs, and since
    // inline codes tint against the element base, half the row would render
    // cyan-on-gold and the other half white-on-gold - the split-color glitch on
    // selected multi-code rows (e.g. "^5  Main ^7Mods" showing cyan+gold at once).
    // The pulse loop checks this flag and leaves self-colored rows at pure white.
    self.rainySelfColored = true;
    self.color = (1.0, 1.0, 1.0);
    return text;
}
set_text(text)
{
    if (!isDefined(self) || !isDefined(text))
        return;
    text = self rainyCollapseRowColor(text);
    text = rainyGuardConfigString(text);
    self.text = text;
    self setText(text);
}
unfreezeAllBots()
{
    level.botsFrozen = false;
    level.softStackFreeze = false;
    setDvar("bots_play_move", "1");
    rainyClearGlobalBotFreezePins(false);
    wait 0.10;
    if (!isDefined(level.players))
        return;
    for (i = 0; i < level.players.size; i++)
    {
        bot = level.players[i];
        if (isDefined(bot) && bot isBot())
        {
            if (isDefined(bot.rainyFrozen) && bot.rainyFrozen)
                continue;
            bot SetVelocity((0, 0, 0));
            bot enableweapons();
            bot freezeControls(false);
            bot.rainyIgnoreGlobalBotFreeze = undefined;
            if (isDefined(bot.frozenOrigin))
                bot.frozenOrigin = undefined;
            if (isDefined(bot.frozenAngles))
                bot.frozenAngles = undefined;
            rainyResetBotPath(bot);
        }
    }
}
scatterBotsToWaypoints()
{
    self endon("disconnect");
    if (!isDefined(level.players))
    {
        self thread rainyShowRaisedMessage("^5No players found");
        return;
    }
    if (!isDefined(level.waypoints) || level.waypoints.size <= 0)
    {
        self thread rainyShowRaisedMessage("^5No Bot Warfare waypoints found");
        return;
    }
    count = 0;
    for (i = 0; i < level.players.size; i++)
    {
        bot = level.players[i];
        if (isDefined(bot) && bot isBot())
        {
            wpIndex = randomInt(level.waypoints.size);
            wp = level.waypoints[wpIndex];
            if (isDefined(wp) && isDefined(wp.origin))
            {
                scatterPos = wp.origin + (0, 0, 8);
                bot SetVelocity((0, 0, 0));
                bot SetOrigin(scatterPos);
                // If this bot is supposed to stay frozen (individually pinned, or held by
                // the global Freeze/Unfreeze Bots toggle), re-pin it at the NEW scattered
                // position instead of letting it walk - otherwise freezeBotsLoop's next
                // tick would just snap it right back to wherever it was frozen before this
                // teleport, or (if frozenOrigin got cleared) the freeze would silently stop
                // holding it at all. Matches the same pattern already used by Teleport Bots
                // To Me/Crosshair.
                if (rainyBotShouldStayPinned(bot))
                {
                    bot.frozenOrigin = scatterPos;
                    bot.frozenAngles = bot.angles;
                    if (isDefined(bot.rainyFrozen) && bot.rainyFrozen)
                    {
                        bot.rainyFrozenOrigin = scatterPos;
                        bot.rainyFrozenAngles = bot.angles;
                    }
                }
                else
                {
                    // Drop the stale pre-teleport path so the bot re-routes from its new spot.
                    bot notify("kill_goal");
                    if (isDefined(bot.bot))
                    {
                        bot.bot.next_wp = -1;
                        bot.bot.second_next_wp = -1;
                        bot.bot.last_next_wp = -1;
                        bot.bot.last_second_next_wp = -1;
                    }
                }
                count++;
            }
        }
    }
    self thread rainyShowRaisedMessage("^5Teleported " + count + " Bots To Random Waypoints");
}
anglesToRightLocal(angles)
{
    return anglesToForward(angles + (0, 90, 0));
}
setPassiveBots(enabled)
{
    if (enabled)
    {
        setDvar("bots_loadout_reasonable", "0");
        setDvar("bots_loadout_allow_op", "0");
        setDvar("bots_play_fire", "0");
        setDvar("bots_play_knife", "0");
        setDvar("bots_play_nade", "0");
        setDvar("bots_play_grenade", "0");
        setDvar("bots_play_flash", "0");
        setDvar("bots_play_stun", "0");
        setDvar("bots_play_smoke", "0");
        setDvar("bots_play_take_carepackages", "0");
        setDvar("bots_play_obj", "0");
        setDvar("bots_play_camp", "0");
        setDvar("bots_play_jumpdrop", "0");
        setDvar("bots_play_target_other", "0");
        setDvar("bots_play_killstreak", "0");
        setDvar("bots_play_ads", "0");
        setDvar("bots_play_sprint", "0");
        setDvar("aim_automelee_enabled", "0");
        setDvar("aim_automelee_range", "0");
        level.passiveBotsActive = true;
        level notify("stopPassiveMeleeSuppressor");
        level thread passiveMeleeSuppressor();
        level notify("stopPassiveStuckWatchdog");
        level thread passiveStuckBotWatchdog();
    }
    else
    {
        level.passiveBotsActive = false;
        level notify("stopPassiveMeleeSuppressor");
        level notify("stopPassiveStuckWatchdog");
        if (isDefined(level.players))
        {
            for (i = 0; i < level.players.size; i++)
            {
                bot = level.players[i];
                if (isDefined(bot) && bot isBot())
                {
                    bot.rainyStuckWatcherRunning = undefined;
                    // Same reasoning as the line above: stopPassiveStuckWatchdog kills
                    // rainyPerBotStuckDeathReset via its own endon, but that leaves this
                    // flag stale-true. Without clearing it here, toggling the system back
                    // ON later would have passiveStuckBotWatchdog's poll loop see a "true"
                    // flag for an actually-dead thread and never spawn a fresh one for
                    // that bot - same stale-flag bug this whole fix exists to prevent.
                    bot.rainyStuckDeathResetRunning = undefined;
                }
            }
        }
        setDvar("bots_loadout_reasonable", "1");
        setDvar("bots_loadout_allow_op", "1");
        setDvar("bots_play_fire", "1");
        setDvar("bots_play_knife", "1");
        setDvar("bots_play_nade", "1");
        setDvar("bots_play_grenade", "1");
        setDvar("bots_play_flash", "1");
        setDvar("bots_play_stun", "1");
        setDvar("bots_play_smoke", "1");
        setDvar("bots_play_take_carepackages", "1");
        setDvar("bots_play_obj", "1");
        setDvar("bots_play_camp", "1");
        setDvar("bots_play_jumpdrop", "1");
        setDvar("bots_play_target_other", "1");
        setDvar("bots_play_killstreak", "1");
        setDvar("bots_play_ads", "1");
        setDvar("bots_play_sprint", "1");
        setDvar("aim_automelee_enabled", "1");
        setDvar("aim_automelee_range", "128");
    }
}
togglePassiveBots()
{
    if (!isDefined(level.passiveBotsActive))
        level.passiveBotsActive = false;
    if (!level.passiveBotsActive)
    {
        setPassiveBots(true);
        self thread rainyShowRaisedMessage("^7Bot Combat ^7[^5OFF^7]");
    }
    else
    {
        setPassiveBots(false);
        self thread rainyShowRaisedMessage("^7Bot Combat ^7[^5ON^7]");
    }
}
rainyEnsureBotTeamDvars()
{
    if (getDvar("bots_team") == "")
        setDvar("bots_team", "autoassign");
    if (getDvar("bots_team_amount") == "")
        setDvar("bots_team_amount", "0");
    if (getDvar("bots_team_force") == "")
        setDvar("bots_team_force", "0");
    if (getDvar("bots_team_mode") == "")
        setDvar("bots_team_mode", "0");
    if (getDvar("bots_skill") == "")
        setDvar("bots_skill", "0");
}
rainyResetBotTeamDifficultyDefaults()
{
    // Reset the Rainy/Bot Warfare Teams and Difficulty submenu back to its
    // release/default state before a map_restart, exitLevel(), or normal final-kill
    // game end can carry these dvars into the next private match.
    setDvar("bots_team", "autoassign");
    setDvar("bots_team_amount", "0");
    setDvar("bots_team_force", "0");
    setDvar("bots_team_mode", "0");
    setDvar("bots_skill", "0");
}
botTeamLabel(team)
{
    if (!isDefined(team) || team == "" || team == "autoassign") return "Autoassign";
    if (team == "allies") return "Allies";
    if (team == "axis") return "Axis";
    if (team == "custom") return "Custom";
    return team;
}
botTeamModeLabel(mode)
{
    if (mode == 1) return "Bots Only";
    return "Everyone";
}
botSkillLabel(s)
{
    if (s == 0) return "Random / All";
    if (s == 1) return "Too Easy";
    if (s == 2) return "Easy";
    if (s == 3) return "Easy-Med";
    if (s == 4) return "Medium";
    if (s == 5) return "Hard";
    if (s == 6) return "Very Hard";
    if (s == 7) return "Hardest";
    if (s == 8) return "Custom";
    if (s == 9) return "Complete Random";
    return "Unknown";
}
toggleBotChat()
{
    if (getDvarFloat("bots_main_chat") > 0)
    {
        setDvar("bots_main_chat", "0");
        self thread rainyShowRaisedMessage("^7Bot Chat ^7[^5OFF^7]");
    }
    else
    {
        setDvar("bots_main_chat", "1");
        self thread rainyShowRaisedMessage("^7Bot Chat ^7[^5ON^7]");
    }
}
cycleBotTeam()
{
    rainyEnsureBotTeamDvars();
    cur = getDvar("bots_team");

    if (cur == "autoassign")
        next = "allies";
    else if (cur == "allies")
        next = "axis";
    else if (cur == "axis")
        next = "custom";
    else
        next = "autoassign";

    setDvar("bots_team", next);
    self thread rainyShowRaisedMessage("^5Bot Team ^7[^5" + botTeamLabel(next) + "^7]");
    if (isDefined(self.menuOpen) && self.menuOpen)
        self updateMenuHud();
}
adjustAxisBotCount(amount)
{
    rainyEnsureBotTeamDvars();
    cur = getDvarInt("bots_team_amount");

    if (cur < 0 || cur > 18)
        cur = 0;

    next = cur + amount;

    if (next > 18)
        next = 0;
    if (next < 0)
        next = 18;

    setDvar("bots_team_amount", next + "");
    // Two different rows call this with opposite signs - [+] is row 1 (white),
    // [-] is row 2 (cyan) - see teamsdifficulty's HUD render block. The sign of
    // amount is what distinguishes which row called it, so use that to pick
    // the matching label color per call site.
    if (amount > 0)
        self thread rainyShowRaisedMessage("^7Axis Bot Count [+] ^7[^5" + next + "^7]");
    else
        self thread rainyShowRaisedMessage("^5Axis Bot Count [-] ^7[^5" + next + "^7]");
    if (isDefined(self.menuOpen) && self.menuOpen)
        self updateMenuHud();
}
toggleForceBotTeam()
{
    rainyEnsureBotTeamDvars();
    next = 1;
    if (getDvarInt("bots_team_force") != 0)
        next = 0;

    setDvar("bots_team_force", next + "");
    if (next)
        self thread rainyShowRaisedMessage("^7Force Bot Team ^7[^5ON^7]");
    else
        self thread rainyShowRaisedMessage("^7Force Bot Team ^7[^5OFF^7]");

    if (isDefined(self.menuOpen) && self.menuOpen)
        self updateMenuHud();
}
toggleBotTeamTarget()
{
    rainyEnsureBotTeamDvars();
    next = 1;
    if (getDvarInt("bots_team_mode") != 0)
        next = 0;

    setDvar("bots_team_mode", next + "");
    self thread rainyShowRaisedMessage("^5Bot Team Target ^7[^5" + botTeamModeLabel(next) + "^7]");
    if (isDefined(self.menuOpen) && self.menuOpen)
        self updateMenuHud();
}
cycleBotDifficulty()
{
    rainyEnsureBotTeamDvars();
    cur = getDvarInt("bots_skill");
    if (cur < 0 || cur >= 9)
        next = 0;
    else
        next = cur + 1;

    setDvar("bots_skill", next + "");
    self thread rainyShowRaisedMessage("^7Difficulty ^7[^5" + botSkillLabel(next) + "^7]");
    if (isDefined(self.menuOpen) && self.menuOpen)
        self updateMenuHud();
}
passiveMeleeSuppressor()
{
    level endon("game_ended");
    level endon("rainy_shutdown");
    level endon("stopPassiveMeleeSuppressor");
    for (;;)
    {
        if (!isDefined(level.players))
        {
            wait 0.5;
            continue;
        }
        setDvar("aim_automelee_enabled", "0");
        setDvar("aim_automelee_range", "0");
        setDvar("bots_play_knife", "0");
        setDvar("bots_play_fire", "0");
        setDvar("bots_play_nade", "0");
        setDvar("bots_play_grenade", "0");
        setDvar("bots_play_flash", "0");
        setDvar("bots_play_stun", "0");
        setDvar("bots_play_smoke", "0");
        setDvar("bots_play_sprint", "0");
        for (i = 0; i < level.players.size; i++)
        {
            bot = level.players[i];
            if (isDefined(bot) && bot isBot() && isAlive(bot))
            {
                if (bot hasWeapon("frag_grenade_mp"))
                    bot setWeaponAmmoStock("frag_grenade_mp", 0);
                if (bot hasWeapon("semtex_mp"))
                    bot setWeaponAmmoStock("semtex_mp", 0);
                if (bot hasWeapon("flash_grenade_mp"))
                    bot setWeaponAmmoStock("flash_grenade_mp", 0);
                if (bot hasWeapon("concussion_grenade_mp"))
                    bot setWeaponAmmoStock("concussion_grenade_mp", 0);
                if (bot hasWeapon("smoke_grenade_mp"))
                    bot setWeaponAmmoStock("smoke_grenade_mp", 0);
                if (bot hasWeapon("claymore_mp"))
                    bot setWeaponAmmoStock("claymore_mp", 0);
                if (bot hasWeapon("c4_mp"))
                    bot setWeaponAmmoStock("c4_mp", 0);
            }
        }
        wait 0.5;
    }
}
passiveStuckBotWatchdog()
{
    // v1 polled position every second, only acting after ~12s of zero net progress.
    // Slow, and blind to level.botsFrozen — it fought the Freeze/Unfreeze Bots toggle by
    // relocating intentionally-frozen bots.
    //
    // v2 switched to listening for the bot warfare engine's own "stuck" bot_event,
    // fired from inside movetowards()'s stuck-detect loop. Faster and more precise
    // when it fires — but it turns out it doesn't always fire. walk_loop() picks a
    // PURE RANDOM waypoint as its roam goal with no reachability check at all (see
    // walk_loop() in _bot_internal.gsc). If initAStar() can't find any path to that
    // random goal, doWalk() skips its waypoint-chain loop entirely and falls through
    // to the bottom fallback `self movetowards(goal)` against the raw, unreachable
    // goal — and depending on exactly how the bot collides with nearby geometry, that
    // call can fail to ever satisfy its own "haven't moved" check cleanly, or the bot
    // simply never gets a walk goal issued again if it's wedged tightly enough that
    // doWalk()'s preconditions silently never re-trigger. Either way: no "stuck"
    // event, bot just sits there indefinitely. This is the walkway-railing case.
    //
    // v3 kept the event listener as the fast path, and ALSO ran a slower,
    // position-based poll as a comprehensive fallback that doesn't depend on the
    // engine successfully detecting its own stuck state at all — it just directly
    // checks "has this bot's position actually changed." Both paths converge on the
    // same relocate function and both correctly respect all freeze states (menu-level
    // botsFrozen/rainyFrozen AND the bot warfare engine's own BotIsFrozen()/stop_move).
    //
    // v4 (this version) fixes a hole found analyzing a highrise case where a bot got
    // stuck under a walkway with NEITHER v3 path catching it. The engine's own
    // movetowards() stuck-detect branch doesn't just notify "stuck" — it ALSO issues a
    // small strafe via botSetMoveTo() to try to self-recover. Against tight geometry
    // that strafe can repeatedly fail to free the bot while still being large enough
    // to read as "movement" to the v3 poller's frame-to-frame distance check, which
    // reset its stuckSeconds counter every cycle. The v3 listener was vulnerable too —
    // it dropped the "stuck" signal entirely on a missed rate-limit slot, trusting the
    // poller as backup, when the poller was the one being fooled by the same strafe.
    // v4's poller now tracks a sticky anchor point that only advances on genuine
    // escape distance, so in-place oscillation can't keep resetting the clock. v4's
    // listener now counts consecutive "stuck" events (which the engine keeps firing
    // every ~3s for a genuinely wedged bot) and escalates to a forced relocate once
    // they repeat, instead of giving up after a single missed slot claim.
    //
    // This loop also spawns rainyPerBotStuckDeathReset() once per bot (separately
    // gated via rainyStuckDeathResetRunning, NOT rainyStuckWatcherRunning - see that
    // function's own comment for why these need separate flags). Bug found in
    // Stability Review: rainyPerBotStuckListener/Poller both self endon("death"),
    // which silently kills them on every bot death, but neither one ever reset
    // rainyStuckWatcherRunning back to false/undefined on the way out. Since this
    // loop only (re)spawns the listener/poller pair when that flag reads false, a
    // bot that died even once would have its flag stuck true forever after - this
    // loop would skip it on every future poll, leaving that bot's stuck-detection
    // permanently dead for the rest of the match even after it respawned and kept
    // playing normally.
    level endon("game_ended");
    level endon("rainy_shutdown");
    level endon("stopPassiveStuckWatchdog");
    for (;;)
    {
        if (!isDefined(level.players))
        {
            wait 0.5;
            continue;
        }
        for (i = 0; i < level.players.size; i++)
        {
            bot = level.players[i];
            if (!isDefined(bot) || !bot isBot())
                continue;
            if (!isDefined(bot.rainyStuckDeathResetRunning) || !bot.rainyStuckDeathResetRunning)
            {
                bot.rainyStuckDeathResetRunning = true;
                bot thread rainyPerBotStuckDeathReset();
            }
            if (isDefined(bot.rainyStuckWatcherRunning) && bot.rainyStuckWatcherRunning)
                continue;
            bot.rainyStuckWatcherRunning = true;
            bot thread rainyPerBotStuckListener();
            bot thread rainyPerBotStuckPoller();
        }
        wait 1;
    }
}
rainyBotIsSafeToRelocate()
{
    // Shared guard for both the event listener and the poller: never touch a bot
    // that's intentionally stationary, whether that's the mod menu's own freeze
    // state or the bot warfare engine's internal frozen/stop_move state.
    if (!isDefined(level.passiveBotsActive) || !level.passiveBotsActive)
        return false;
    if (isDefined(level.botsFrozen) && level.botsFrozen)
        return false;
    if (isDefined(self.rainyFrozen) && self.rainyFrozen)
        return false;
    if (self BotIsFrozen())
        return false;
    return true;
}
rainyTryClaimRelocateSlot()
{
    // Global, map-wide rate limiter for bot relocations. Each relocate calls
    // rainyResetBotPath(), which fires kill_goal and nulls the bot's cached waypoints,
    // forcing the engine to run a fresh from-scratch A* search on that bot's next think.
    // A full A* search is the single most expensive pathfinding event in Bot Warfare.
    //
    // On a small, densely-connected map like Rust, the engine's per-frame pathfinding
    // budget is already near its limit around 13-14 bots (each bot's A* search touches a
    // large fraction of the same waypoint graph). When 14+ bots clump under the center
    // tower and a wave of them trips the stuck check together, the old code forced that
    // entire wave of A* recomputes in the same frame - pushing the server over its frame
    // deadline and producing the choppiness that only showed up past ~14 bots on Rust.
    //
    // This cap converts a synchronized burst into a steady trickle: at most
    // RELOCATES_PER_SECOND forced path resets happen map-wide per second, no matter how
    // many bots are stuck at once. Stuck bots simply wait their turn across the next few
    // poll cycles instead of all relocating on one frame. The clump still clears, just
    // spread over time so the engine's pathfinder never gets a synchronized spike.
    relocatesPerSecond = 3;
    now = getTime();
    if (!isDefined(level.rainyRelocateWindowStart))
    {
        level.rainyRelocateWindowStart = now;
        level.rainyRelocateCountThisWindow = 0;
    }
    // Reset the 1-second window if it has elapsed.
    if (now - level.rainyRelocateWindowStart >= 1000)
    {
        level.rainyRelocateWindowStart = now;
        level.rainyRelocateCountThisWindow = 0;
    }
    if (level.rainyRelocateCountThisWindow >= relocatesPerSecond)
        return false;
    level.rainyRelocateCountThisWindow++;
    return true;
}
rainyPerBotStuckDeathReset()
{
    // Companion to rainyPerBotStuckListener/Poller, spawned once per bot by
    // passiveStuckBotWatchdog (gated by its OWN flag, rainyStuckDeathResetRunning -
    // deliberately NOT rainyStuckWatcherRunning, since that flag's whole problem is
    // that it goes stale on death; gating this thread behind the same flag it exists
    // to fix would just move the bug here instead of solving it).
    //
    // This is the only one of the three per-bot threads that must NOT self endon
    // ("death") - it needs to survive every individual death of this bot for the
    // rest of the match, since bots respawn as the same persistent script entity
    // here (same pattern rainyFovPersistLoop already relies on for re-applying FOV
    // on every "spawned_player") rather than being recreated fresh. Each death
    // resets rainyStuckWatcherRunning back to false, so passiveStuckBotWatchdog's
    // own poll loop picks this bot back up and spawns a fresh listener/poller pair
    // for its next life, instead of leaving that bot's stuck-detection permanently
    // skipped after its first death.
    self endon("disconnect");
    self endon("stopPassiveStuckWatchdog");
    level endon("game_ended");
    level endon("rainy_shutdown");
    for (;;)
    {
        self waittill("death");
        self.rainyStuckWatcherRunning = undefined;
    }
}
rainyPerBotStuckListener()
{
    // Fast path: react the instant the bot warfare engine's own stuck-detect fires.
    //
    // Bug found analyzing a highrise walkway-railing case: movetowards()'s own
    // stuck-detect branch (_bot_internal.gsc) does more than just notify "stuck" -
    // in the same breath it issues a small strafe via botSetMoveTo(randomDir) to try
    // to break free on its own. That strafe is genuine, if tiny, displacement. A bot
    // wedged tightly enough can fail to escape via that strafe, get re-wedged, and
    // fire "stuck" again next cycle - over and over - while each individual strafe
    // pulse is just large enough that rainyPerBotStuckPoller's 24-unit frame-to-frame
    // check sees "movement" and resets its own stuckSeconds counter to 0. Meanwhile
    // this listener, if it lost the rate-limit race on an earlier "stuck" event,
    // used to just `continue` and drop that signal entirely, trusting the poller as
    // backup - but the poller was the one being fooled. Net effect: the bot oscillates
    // forever, both detectors individually satisfied that "it's not stuck", endlessly.
    //
    // Fix: track consecutive stuck events with no successful relocate in between. If
    // the rate limiter blocks a claim, don't drop the signal - keep counting. Once
    // a bot has fired "stuck" repeatedly in a short window, that pattern alone is
    // proof of a wedge regardless of whether a stray strafe pulse moved it a few
    // units, so escalate to relocate as soon as a slot opens rather than requiring
    // the poller's independent confirmation.
    self endon("disconnect");
    self endon("death");
    self endon("stopPassiveStuckWatchdog");
    level endon("game_ended");
    level endon("rainy_shutdown");
    consecutiveStucks = 0;
    lastStuckTime = 0;
    for (;;)
    {
        self waittill("bot_event", msg);
        if (!isDefined(msg) || msg != "stuck")
            continue;
        if (!self rainyBotIsSafeToRelocate())
        {
            consecutiveStucks = 0;
            continue;
        }
        now = getTime();
        // Consecutive only counts if events are close together (within 5s of each
        // other) - a "stuck" event from an unrelated moment hours apart shouldn't
        // chain onto this one.
        if (lastStuckTime != 0 && (now - lastStuckTime) > 5000)
            consecutiveStucks = 0;
        lastStuckTime = now;
        consecutiveStucks++;
        // Keep retrying the slot claim every cycle instead of giving up after one
        // miss - a bot that's genuinely wedged will keep re-firing "stuck" on its
        // own every ~3s (the engine's internal cycle), so it gets another chance
        // here rather than relying solely on the slower poller.
        if (!rainyTryClaimRelocateSlot())
            continue;
        // Either this is the first stuck signal (give the engine's own strafe-escape
        // a chance first) or it's repeated enough in a row to be a confirmed wedge -
        // relocate immediately rather than waiting on poller confirmation that the
        // strafe pulses can defeat.
        if (consecutiveStucks >= 2)
        {
            self rainyRelocateStuckBotToNeighborWaypoint();
            consecutiveStucks = 0;
        }
    }
}
rainyPerBotStuckPoller()
{
    // Fallback path: catches bots that never trigger the engine's own "stuck" event
    // at all (no reachable A* path to a random roam goal, wedged against geometry
    // tightly enough that doWalk() preconditions never re-fire, etc). Runs slower
    // and requires a longer confirmed-stationary window than the event path, since
    // it has no help from the engine's own detection and needs to avoid false
    // positives against bots that are just legitimately standing still briefly.
    //
    // Fixed: lastOrigin used to be overwritten every single sample regardless of
    // whether the bot had actually escaped its spot, so a bot doing small in-place
    // strafe pulses (e.g. the engine's own stuck-recovery strafe, repeatedly failing
    // against tight geometry) could keep nudging just past the 24-unit threshold each
    // second relative to the PREVIOUS sample, resetting stuckSeconds every time even
    // though the bot's overall position over many seconds never goes anywhere. Now
    // lastOrigin is a sticky anchor: it only moves once the bot has gotten a real
    // distance away from it, so oscillation around one spot can't keep resetting the
    // clock the way frame-to-frame deltas could.
    self endon("disconnect");
    self endon("death");
    self endon("stopPassiveStuckWatchdog");
    level endon("game_ended");
    level endon("rainy_shutdown");
    anchorOrigin = undefined;
    stuckSeconds = 0;
    // Real escape distance from the anchor - bigger than a single stuck-strafe pulse
    // so genuine wedge-oscillation can't satisfy it, but still well short of a normal
    // walking bot's per-second travel distance.
    escapeDist = 48;
    for (;;)
    {
        wait 1;
        if (!self rainyBotIsSafeToRelocate())
        {
            anchorOrigin = undefined;
            stuckSeconds = 0;
            continue;
        }
        if (!isDefined(anchorOrigin))
        {
            anchorOrigin = self.origin;
            stuckSeconds = 0;
            continue;
        }
        if (distanceSquared(self.origin, anchorOrigin) < (escapeDist * escapeDist))
        {
            // Still within escape range of the anchor - counts as stuck even if this
            // particular sample drifted a little from the last one.
            stuckSeconds++;
        }
        else
        {
            // Bot has genuinely put real distance behind it - move the anchor and
            // restart the clock.
            anchorOrigin = self.origin;
            stuckSeconds = 0;
        }
        // 6 confirmed-stationary seconds: long enough that a bot just pausing at a
        // corner or finishing a goal isn't caught, short enough that it doesn't look
        // like the old 12s "sit there, then teleport" pattern.
        if (stuckSeconds >= 6)
        {
            // Respect the global relocation cap. If no slot is free this second, leave
            // the bot flagged as stuck (don't reset the timer) so it stays a candidate
            // and gets relocated on a later poll cycle once the burst clears, instead of
            // forcing every clumped bot's A* reset into the same frame.
            if (rainyTryClaimRelocateSlot())
            {
                self rainyRelocateStuckBotToNeighborWaypoint();
                stuckSeconds = 0;
                anchorOrigin = self.origin;
            }
        }
    }
}
rainyRelocateStuckBotToNeighborWaypoint()
{
    if (!isDefined(level.waypoints) || level.waypoints.size <= 0)
    {
        rainyResetBotPath(self);
        return;
    }
    nearestIdx = -1;
    nearestDist = -1;
    for (i = 0; i < level.waypoints.size; i++)
    {
        wp = level.waypoints[i];
        if (!isDefined(wp) || !isDefined(wp.origin))
            continue;
        d = distanceSquared(self.origin, wp.origin);
        if (nearestIdx == -1 || d < nearestDist)
        {
            nearestIdx = i;
            nearestDist = d;
        }
    }
    if (nearestIdx == -1)
    {
        rainyResetBotPath(self);
        return;
    }
    nearestWp = level.waypoints[nearestIdx];
    targetOrigin = nearestWp.origin;
    // Prefer an actual connected neighbor over the nearest waypoint itself — that's a
    // real step along the graph rather than just snapping back to where it likely
    // already was stuck near.
    if (isDefined(nearestWp.children) && nearestWp.children.size > 0)
    {
        childIdx = nearestWp.children[randomInt(nearestWp.children.size)];
        if (isDefined(level.waypoints[childIdx]) && isDefined(level.waypoints[childIdx].origin))
            targetOrigin = level.waypoints[childIdx].origin;
    }
    self SetVelocity((0, 0, 0));
    self SetOrigin(targetOrigin + (0, 0, 8));
    rainyResetBotPath(self);
}
toggleForceUAV()
{
    if (!isDefined(level.forceUAV))
        level.forceUAV = false;
    level notify("stopForceUAV"); // stop any running Force UAV monitor first
    level.forceUAV = !level.forceUAV;
    self.forceUAV = level.forceUAV;
    if (level.forceUAV)
    {
        level thread forceUAVLoop();
        self thread rainyShowRaisedMessage("^5Force UAV ^7[^5ON^7]");
    }
    else
    {
        setForceUAVDvars(false);
        self thread rainyShowRaisedMessage("^5Force UAV ^7[^5OFF^7]");
    }
}
toggleKillcams()
{
    // Per-player: only flips THIS player's preference (the host's). The global
    // level.killcam gate must remain enabled because stock _damage.gsc checks it later;
    // OFF is host-only through self.cancelKillcam, not by globally disabling killcams.
    if (!isDefined(self.rainyKillcamsEnabled))
        self.rainyKillcamsEnabled = false;
    self.rainyKillcamsEnabled = !self.rainyKillcamsEnabled;
    rainyEnsureGlobalKillcamAvailable();
    self rainyApplyKillcamPreference();
    if (self.rainyKillcamsEnabled)
    {
        // Turning your own killcams back ON re-introduces the killcam HUD elements, which
        // on a full per-client HUD pool can starve your menu's last element (the header
        // line). That is the documented trade-off you opt into here.
        self thread rainyShowRaisedMessage("^7Killcams ^7[^5ON^7] ^7(your menu HUD may drop 1 element after a killcam)");
    }
    else
    {
        self thread rainyShowRaisedMessage("^7Killcams ^7[^5OFF^7]");
    }
}

rainyEnsureGlobalKillcamAvailable()
{
    // The stock death flow needs level.killcam true before it will launch any normal
    // killcam. Earlier menu logic could leave this global false, which also makes the
    // Copycat deathstreak prompt appear while never actually restoring the killcam.
    if (!isDefined(level.killcam) || !level.killcam)
        level.killcam = true;
}

rainyApplyKillcamPreference()
{
    // Only the menu holder/host owns this preference right now. Non-host players should
    // keep the stock killcam behavior and should not have their skip/cancel state touched.
    if (isDefined(self.rainyWasHost) && !self.rainyWasHost)
        return;
    if (!isDefined(self.rainyKillcamsEnabled))
        return;

    rainyEnsureGlobalKillcamAvailable();

    if (self.rainyKillcamsEnabled)
    {
        // Explicit false matters here. Leaving this undefined/true from the OFF state can
        // continue suppressing the host's killcam even after the menu says ON.
        self.cancelKillcam = false;
        return;
    }

    self.cancelKillcam = true;
}

rainyKillcamPreferenceLoop()
{
    self endon("disconnect");
    level endon("game_ended");
    level endon("rainy_shutdown");
    if (isDefined(self.rainyWasHost) && !self.rainyWasHost)
        return;
    for (;;)
    {
        // Keep the global gate open so the ON toggle can work, but only keep touching
        // cancelKillcam while the host's Killcams setting is OFF. When ON, stock
        // _killcam::cancelKillCamOnUse() should be allowed to manage skip behavior.
        rainyEnsureGlobalKillcamAvailable();
        if (isDefined(self.rainyKillcamsEnabled) && !self.rainyKillcamsEnabled)
            self.cancelKillcam = true;
        wait 0.10;
    }
}
forceUAVLoop()
{
    // Polls every 0.2s (instead of every 2s) so any external reset of these
    // dvars -- entering UFO, leaving UFO (unlink), respawning, anything -- gets
    // caught quickly without polling at a full-tickrate cadence. This is the
    // single source of truth for keeping Force UAV on; it no longer matters
    // whether UFO is active or not. (Was 0.05s during private testing; slowed
    // for release since 20 polls/sec across several players/bots was more
    // frequent than this needed to be - see Stability Review.)
    level endon("stopForceUAV");
    level endon("game_ended");
    level endon("rainy_shutdown");
    for (;;)
    {
        setForceUAVDvars(true);
        wait 0.2;
    }
}
setForceUAVDvars(enabled)
{
    if (enabled)
    {
        setDvar("compassEnemyFootstepEnabled", "1");
        setDvar("compassEnemyFootstepMaxRange", "2147483647");
        setDvar("compassEnemyFootstepMaxZ", "2147483647");
        setDvar("compassEnemyFootstepMinSpeed", "0");
    }
    else
    {
        setDvar("compassEnemyFootstepEnabled", "0");
        setDvar("compassEnemyFootstepMaxRange", "500");
        setDvar("compassEnemyFootstepMaxZ", "100");
        setDvar("compassEnemyFootstepMinSpeed", "140");
    }
    // Also push directly to each client. Same reasoning as cg_fov: some of these
    // are client-saved dvars that the client can silently revert to its own
    // config value (most likely exactly when UFO links/unlinks the player), and
    // the global setDvar call alone doesn't always force through on the client.
    if (!isDefined(level.players))
        return;
    for (i = 0; i < level.players.size; i++)
    {
        player = level.players[i];
        if (!isDefined(player))
            continue;
        // Guard against acting on a stale/disconnecting entity. isDefined() alone
        // doesn't always catch a player mid-disconnect during level teardown (e.g.
        // leaving the lobby), and this loop runs frequently (every 0.2s while
        // Force UAV is active) and calls _unsetPerk below, a state-mutating native
        // call - exactly the kind of call that's risky to make on an entity the
        // engine is simultaneously tearing down. sessionstate=="playing" is the
        // same validity check already used elsewhere in this file (see the
        // closest-target search) for confirming a player is genuinely active.
        if (!isDefined(player.sessionstate) || player.sessionstate != "playing")
            continue;
        if (enabled)
        {
            player setClientDvar("compassEnemyFootstepEnabled", "1");
            player setClientDvar("compassEnemyFootstepMaxRange", "2147483647");
            player setClientDvar("compassEnemyFootstepMaxZ", "2147483647");
            player setClientDvar("compassEnemyFootstepMinSpeed", "0");
            /*
                Cold-Blooded makes a player undetectable by UAVs/killstreaks at the engine
                level, tied directly to having the perk equipped - there is no separate
                dvar to bypass just that immunity while leaving the perk's other effects
                (no thermal highlight, no red crosshair on Pro) intact. Ninja (and its Pro
                upgrade, specialty_quieter) is also stripped here: this entire Force UAV
                feature is implemented via compassEnemyFootstep* dvars - a footstep-noise
                detection system, not a true persistent UAV - and Ninja's whole purpose is
                reducing footstep noise, which interferes with the same mechanism. So while
                Force UAV is active, both perks are stripped outright from every bot/player
                (host included) on every tick of this same loop - same cadence as the dvar
                push above, so it's caught quickly even if re-equipped via a class change
                or the Give Perks menu. This is a one-way strip: turning Force UAV back OFF
                does not restore either perk to anyone, since there is no reliable record
                of who had what before - if that's ever needed, it would require tracking
                pre-strip perk state per player.
            */
            player _unsetPerk("specialty_coldblooded");
            player _unsetPerk("specialty_NINJA");
            player _unsetPerk("specialty_quieter");
        }
        else
        {
            player setClientDvar("compassEnemyFootstepEnabled", "0");
            player setClientDvar("compassEnemyFootstepMaxRange", "500");
            player setClientDvar("compassEnemyFootstepMaxZ", "100");
            player setClientDvar("compassEnemyFootstepMinSpeed", "140");
        }
    }
}
forceUAVSpawnPersistLoop()
{
    // Mirrors rainyFovPersistLoop. cg_fov needed a dedicated re-apply on every
    // "spawned_player" event because the client reverts saved dvars to its local
    // config on (re)spawn -- and UFO mode's link/unlink sequence triggers exactly
    // that kind of respawn internally. Catch it the same way here.
    self endon("disconnect");
    level endon("game_ended");
    level endon("rainy_shutdown");
    for (;;)
    {
        self waittill("spawned_player");
        if (isDefined(level.forceUAV) && level.forceUAV)
        {
            wait 0.1;
            self setClientDvar("compassEnemyFootstepEnabled", "1");
            self setClientDvar("compassEnemyFootstepMaxRange", "2147483647");
            self setClientDvar("compassEnemyFootstepMaxZ", "2147483647");
            self setClientDvar("compassEnemyFootstepMinSpeed", "0");
        }
    }
}
toggleUFO()
{
    self notify("StopUFO");
    if (!isDefined(self.ufoEnabled))
        self.ufoEnabled = false;
    self.ufoEnabled = !self.ufoEnabled;
    if (self.ufoEnabled)
    {
        self thread rainyShowRaisedMessage("^7UFO Mode ^7[^5ON^7]");
        self thread ufoLoop();
        self thread ufoWeaponSuppressLoop();
        self thread ufoRespawnWatcher();
    }
    else
    {
        self thread rainyShowRaisedMessage("^7UFO Mode ^7[^5OFF^7]");
        self rainyTearDownUfo();
    }
}
/*
    Just the cleanup part of turning UFO off (unlink, re-enable weapons, stop
    velocity, delete the ufoEntity) with no flip of self.ufoEnabled and no
    "UFO Disabled" print. toggleUFO() uses this when the player explicitly
    turns UFO off via the menu or the aim+standing+Dpad-down bind.

    loadPosition() does NOT use this function - it needs to break the UFO link
    only momentarily (writing position/velocity fights an active playerLinkTo),
    then immediately relink to the same still-alive ufoEntity so UFO keeps
    flying after the load. Going through this function would fully tear UFO
    down (delete the entity, flip ufoEnabled false), which is too heavy-handed
    for a load that should leave UFO state untouched - see loadPosition()'s own
    unlink/move/relink for that lighter-weight approach.

    Confirmed (Stability Review item): every notify("StopUFO") call site in this
    file is immediately followed by a call into this function on the same line/
    statement pair - never a bare notify left to rely on ufoLoop's own endon to
    eventually get around to its own unlink/delete. That's intentional and already
    correct; it means cleanup here is never left waiting on thread scheduling, and
    there's no path where StopUFO fires without this teardown also running in the
    same breath. No fix needed here - documenting so this doesn't get re-flagged
    or "fixed" into something more complicated later.
*/
rainyTearDownUfo()
{
    self.ufoEnabled = false;
    self unlink();
    // ADS+UFO-bind gun glitch, take 3: evidence ruled out the previous two
    // theories (delaying disableweapons in ufoWeaponSuppressLoop, then delaying
    // playerLinkTo in ufoLoop - neither fixed it; see those functions' comments).
    // Decisive test result: the very first ON ever is clean, but every ON after
    // at least one OFF glitches, and OFF itself never visibly glitches. That
    // points at THIS function - specifically unlink() and enableweapons() firing
    // back-to-back with no gap. unlink() hands the player's view/movement back
    // from the UFO script_origin to normal first-person control; enableweapons()
    // immediately after re-grants weapon use while that handoff may still be
    // settling. Nothing bad is visible at the moment OFF happens (no immediate
    // ADS attempt yet), but it's whatever's left in that state by the time the
    // player next tries to ADS that produces the glitch - which only exists
    // after a full unlink+enableweapons cycle has happened at least once.
    // Small gap added here so the unlink settles before weapons re-enable.
    wait 0.1;
    self enableweapons();
    self SetVelocity((0, 0, 0));
    if (isDefined(self.ufoEntity))
    {
        self.ufoEntity delete();
        self.ufoEntity = undefined;
    }
}
/*
    Removes the player's current topmost/active killstreak (self.pers["killstreaks"][0] -
    the one shown on the HUD and currently equipped in the killstreak weapon slot), then
    shifts every remaining killstreak down one index so whatever was second in line becomes
    the new active one. This mirrors the stock engine's own shuffle pattern used when a
    killstreak is used/consumed (see maps\mp\killstreaks\_killstreaks::shuffleKillStreaksFILO),
    just targeting index 0 directly instead of searching for a specific streakName.

    After the shuffle, the player's actual held killstreak weapon is re-synced: if another
    killstreak is now on top, they're given that killstreak's weapon (mirrors
    giveOwnedKillstreakItem); if the list is now empty, the killstreak weapon is taken away
    entirely so they aren't left holding a laptop/remote for a streak that no longer exists.
*/
rainyRemoveTopKillstreak()
{
    if (!isDefined(self.pers["killstreaks"]) || !isDefined(self.pers["killstreaks"][0]))
    {
        self thread rainyShowRaisedMessage("^5No Killstreak To Remove");
        return;
    }
    removedName = self.pers["killstreaks"][0].streakName;
    arraySize = self.pers["killstreaks"].size;
    for (i = 0; i < arraySize; i++)
    {
        if (i == arraySize - 1)
        {
            self.pers["killstreaks"][i] = undefined;
        }
        else
        {
            self.pers["killstreaks"][i] = self.pers["killstreaks"][i + 1];
        }
    }
    if (isDefined(self.pers["killstreaks"][0]))
    {
        newWeapon = maps\mp\killstreaks\_killstreaks::getKillstreakWeapon(self.pers["killstreaks"][0].streakName);
        self maps\mp\killstreaks\_killstreaks::giveKillstreakWeapon(newWeapon);
    }
    else
    {
        weaponList = self getWeaponsListItems();
        foreach (item in weaponList)
        {
            if (!isSubStr(item, "killstreak"))
                continue;
            self takeWeapon(item);
        }
        self _setActionSlot(4, "");
    }
    if (isDefined(removedName))
        self thread rainyShowRaisedMessage("^5Removed Killstreak: " + removedName);
    else
        self thread rainyShowRaisedMessage("^5Killstreak Removed");
}
/*
    Lobby Options - Set Gamemode: changes g_gametype and restarts the map, since
    IW4x requires a map restart for a gametype change to actually take effect (the
    rules can update live, but the gametype itself cannot). Mirrors the existing
    "Restart Game" button's reset-then-restart sequence so transient mod state
    (FOV, speed, etc.) doesn't carry over into the new gametype.
    gametype: "dm" = FFA, "war" = TDM, "sd" = Search and Destroy.
*/
rainyChangeGametype(gametype)
{
    label = "FFA";
    if (gametype == "war")
        label = "TDM";
    else if (gametype == "sd")
        label = "SND";
    setDvar("g_gametype", gametype);
    self closeMenuHud();
    rainyResetTransientSettingsAllPlayers();
    // Each gametype value maps to exactly one setgamemode row (see that page's HUD
    // render block): "dm"->row0(cyan), "war"->row1(white), "sd"->row2(cyan).
    if (gametype == "war")
        self thread rainyShowRaisedMessage("^7Changing Gamemode To " + label + "...");
    else
        self thread rainyShowRaisedMessage("^5Changing Gamemode To " + label + "...");
    wait 0.3;
    map_restart(false);
}
cyclePlayerHealth()
{
    if (!isDefined(level.healthLevel))
        level.healthLevel = 1;

    // Display cycle: Normal > Miniscule > 1 HP > Half > Double > Normal
    // Internal level values stay the same so each health option keeps its original effect.
    if (level.healthLevel == 1)       level.healthLevel = 3;
    else if (level.healthLevel == 3)  level.healthLevel = 4;
    else if (level.healthLevel == 4)  level.healthLevel = 2;
    else if (level.healthLevel == 2)  level.healthLevel = 5;
    else                             level.healthLevel = 1;

    // Everyone's REAL health stays at 100, so the engine never enters its low-health
    // state and never plays the heartbeat / panting / red overlay. The lobby is made
    // fragile (or tanky) purely by scaling incoming damage in rainyPlayerDamageHook.
    // effHP is the health the lobby should "feel" like it has.
    effHP = 100;
    if (level.healthLevel == 2)       effHP = 50;
    else if (level.healthLevel == 3)  effHP = 10;
    else if (level.healthLevel == 4)  effHP = 1;
    else if (level.healthLevel == 5)  effHP = 200;
    level.healthDamageMult = 100.0 / effHP;
    for (i = 0; i < level.players.size; i++)
    {
        p = level.players[i];
        if (!isDefined(p))
            continue;
        if (isDefined(p.godMode) && p.godMode)
            continue;
        if (isAlive(p))
        {
            p.maxhealth = 100;
            p.health = 100;
        }
    }
    if (level.healthLevel == 1)       self thread rainyShowRaisedMessage("^7Lobby Health ^7[^5Normal^7]");
    else if (level.healthLevel == 2)  self thread rainyShowRaisedMessage("^7Lobby Health ^7[^5Half^7]");
    else if (level.healthLevel == 3)  self thread rainyShowRaisedMessage("^7Lobby Health ^7[^5Miniscule^7]");
    else if (level.healthLevel == 4)  self thread rainyShowRaisedMessage("^7Lobby Health ^7[^51HP^7]");
    else if (level.healthLevel == 5)  self thread rainyShowRaisedMessage("^7Lobby Health ^7[^5Double^7]");
}

/*
    Hooks the player-damage callback so the lobby health levels can scale damage
    instead of lowering real health (which is what triggered the "almost dead"
    breathing). When health is Normal (mult 1.0) this is a transparent pass-through.
*/
installRainyDamageHook()
{
    level endon("rainy_shutdown");

    // NOTE: deliberately no level endon("game_ended") here. The old version ended this
    // thread on "game_ended" while still polling for level.callbackPlayerDamage to exist;
    // if that notify ever fired before the callback was defined (round restart / warmup
    // transition timing), this thread died silently and the damage hook never installed
    // for the rest of the match.
    if (isDefined(level.rainyDamageHooked) && level.rainyDamageHooked)
        return; // already installed, never run this twice
    while (!isDefined(level.callbackPlayerDamage))
        wait 0.05;
    // Bot Warfare installs its own callbackPlayerDamage hook (_bot.gsc) on its own
    // timer. Waiting here gives it a chance to install first if it hasn't already, so
    // we capture ITS handler as "previous" and end up as the outermost hook, with Bot
    // Warfare's chain still fully reachable through level.rainyOrigPlayerDamage.
    //
    // IMPORTANT: this install must run EXACTLY ONCE, guarded only by rainyDamageHooked
    // (a plain flag), never by comparing level.callbackPlayerDamage against
    // ::rainyPlayerDamageHook. An earlier version used a recurring "watchdog" thread
    // that re-checked and re-pointed the callback every couple seconds using a function
    // pointer equality check - GSC function pointer comparisons across separate thread
    // contexts are not reliable on this build, and a false-negative there produced
    // level.rainyOrigPlayerDamage = ::rainyPlayerDamageHook (the hook pointing at
    // itself). Every hit then recursed into itself instead of ever reaching the real
    // engine damage logic, which silently ate kills entirely and left the engine's
    // weapon-drop/death-drop logic firing inconsistently (the drop-and-repickup
    // behavior). A single one-time install removes that failure mode completely.
    wait 1;
    level.rainyOrigPlayerDamage = level.callbackPlayerDamage;
    level.callbackPlayerDamage = ::rainyPlayerDamageHook;
    level.rainyDamageHooked = true;
}
rainyEntityIsTrackedPlayer(ent)
{
    // True for any entity that is a real connected client OR a Bot Warfare bot -
    // both occupy slots in level.players in this setup, unlike isPlayer() which is
    // not guaranteed to recognize AI-controlled bot slots the same way. Checking
    // level.players directly matches how every other part of this menu treats bots
    // and players identically (see rainyIsBot(), clientList building, etc).
    if (!isDefined(ent) || !isDefined(level.players))
        return false;
    for (i = 0; i < level.players.size; i++)
    {
        if (level.players[i] == ent)
            return true;
    }
    return false;
}
rainyIsSniperRifle(weaponName)
{
    // The 6 sniper rifles available in MW2 (IW4x). Debug logging showed getCurrentWeapon()
    // can hand back a name like "fire_weapon_cheytac_fmj_mp" instead of a clean
    // "cheytac_mp" - getBaseWeaponName() on this build does not strip that leading
    // "fire_weapon_" prefix the way it strips trailing attachment suffixes, so an exact
    // match against the base name silently failed for every shot. issubstr() against
    // the raw weapon name (not just the "base" name) makes this resilient to whatever
    // prefix/suffix soup the engine actually hands back, fmj or otherwise.
    if (!isDefined(weaponName))
        return false;
    if (issubstr(weaponName, "cheytac"))  return true;
    if (issubstr(weaponName, "barrett"))  return true;
    if (issubstr(weaponName, "wa2000"))   return true;
    if (issubstr(weaponName, "m21"))      return true;
    if (issubstr(weaponName, "m40a3"))    return true;
    if (issubstr(weaponName, "dragunov")) return true;
    return false;
}
rainyBroadcastMessage(msg)
{
    if (isDefined(level.rainyLevelShuttingDown) && level.rainyLevelShuttingDown)
        return;

    // Stock-killfeed style implementation:
    // - No moving HUD elements.
    // - Four fixed rows live in the lower-left area.
    // - A new entry is written into the bottom row and older entries are shifted
    //   one row upward by data/slot refresh only. Because the HUD elements never
    //   change X position or run moveOverTime(), there is no right-to-left fly-in.
    if (!isDefined(level.players))
        return;

    for (i = 0; i < level.players.size; i++)
    {
        p = level.players[i];
        if (!isDefined(p))
            continue;
        if (p isBot())
            continue;

        p rainyQueueBroadcastMessage(msg);
    }
}
rainyQueueBroadcastMessage(msg)
{
    if (!isDefined(self.rainyBroadcastQueue))
        self.rainyBroadcastQueue = [];

    self.rainyBroadcastQueue[self.rainyBroadcastQueue.size] = msg;

    if (!isDefined(self.rainyBroadcastQueueRunning) || !self.rainyBroadcastQueueRunning)
    {
        self.rainyBroadcastQueueRunning = true;
        self thread rainyBroadcastQueueProcessor();
    }
}
rainyBroadcastQueueProcessor()
{
    self endon("disconnect");
    self endon("rainy_broadcast_shutdown");
    level endon("game_ended");
    level endon("rainy_shutdown");

    while (true)
    {
        if (!isDefined(self.rainyBroadcastQueue) || self.rainyBroadcastQueue.size <= 0)
        {
            self.rainyBroadcastQueueRunning = false;
            return;
        }

        msg = self.rainyBroadcastQueue[0];
        newQueue = [];
        writeIndex = 0;

        for (i = 1; i < self.rainyBroadcastQueue.size; i++)
        {
            newQueue[writeIndex] = self.rainyBroadcastQueue[i];
            writeIndex++;
        }

        self.rainyBroadcastQueue = newQueue;
        self rainyAddBroadcastFeedEntry(msg);

        // Small spacing prevents same-frame multi-kills from clobbering the slot
        // refresh order, but keeps the feed feeling instant.
        wait 0.04;
    }
}
rainyPostGameBroadcastGraceSeconds()
{
    // Long enough for final-kill distance/hitmarker/almost-hit messages to be visible
    // during the stock postgame scoreboard/credits, but short enough that HUD cleanup
    // still happens before returning to lobby/main-menu flows.
    // Raised by 1.0s to match the adjusted shot-feed hold time below.
    return 8.0;
}
rainyStartPostGameBroadcastRefresh()
{
    if (isDefined(self.rainyPostGameBroadcastRefreshRunning) && self.rainyPostGameBroadcastRefreshRunning)
        return;

    self.rainyPostGameBroadcastRefreshRunning = true;
    self thread rainyPostGameBroadcastRefreshLoop();
}
rainyPostGameBroadcastRefreshLoop()
{
    self endon("disconnect");
    self endon("rainy_broadcast_shutdown");
    level endon("rainy_shutdown");

    endAt = getTime() + int(rainyPostGameBroadcastGraceSeconds() * 1000);

    while (getTime() < endAt)
    {
        // Re-apply the shot-feed text/position while the stock endgame HUD is being
        // built. This protects against the scoreboard/credits pass hiding or starving
        // the existing HUD slots during the first few postgame frames.
        if (isDefined(self.rainyShotFeedMsgs) && self.rainyShotFeedMsgs.size > 0)
            self rainyRenderBroadcastSlots();

        wait 0.10;
    }

    self.rainyPostGameBroadcastRefreshRunning = false;
}
rainyBroadcastBaseX()
{
    return 6;
}
rainyBroadcastBaseY()
{
    // Raised so the shot feed clears the stock lower-left kill/status feed.
    return -204;
}
rainyBroadcastLineGap()
{
    return 20;
}
rainyBroadcastMaxMessages()
{
    // Four feed lines. This no longer competes with the menu's HUD slots: while the mod
    // menu is open the feed releases ALL of its client-HUD slots (see
    // rainyReleaseBroadcastSlotsForMenu / the menuOpen guard in rainyEnsureBroadcastSlots)
    // so the full menu - including the 2px header line - is always 100% intact, even when
    // a killcam has filled the per-client HUD pool. The feed rebuilds when the menu closes.
    return 4;
}
rainyBroadcastHoldTime()
{
    return 5.75;
}
rainyBroadcastFadeTime()
{
    return 0.65;
}
rainyBroadcastHoldTimeMs()
{
    return 5750;
}
rainyBroadcastFadeTimeMs()
{
    return 650;
}
rainyBroadcastSlotY(slot)
{
    return rainyBroadcastBaseY() - (slot * rainyBroadcastLineGap());
}
rainyEnsureBroadcastSlots()
{
    if (isDefined(level.rainyLevelShuttingDown) && level.rainyLevelShuttingDown)
        return;

    // While the mod menu is open the feed yields ALL of its client-HUD slots to the menu
    // so the menu is guaranteed to be 100% intact. A killcam fills the per-client HUD pool
    // enough that the menu plus the feed cannot both fit; rather than starve the menu's
    // last element (the header line), the feed steps aside until the menu is closed, then
    // rebuilds itself on the next message.
    if (isDefined(self.menuOpen) && self.menuOpen)
    {
        self rainyReleaseBroadcastSlotsForMenu();
        return;
    }

    if (isDefined(self.rainyBroadcastSlotHuds) && self.rainyBroadcastSlotHuds.size >= rainyBroadcastMaxMessages())
        return;

    self.rainyBroadcastSlotHuds = [];

    for (i = 0; i < rainyBroadcastMaxMessages(); i++)
    {
        hud = self createFontString("default", 1.35);
        hud setPoint("LEFT", "BOTTOM_LEFT", rainyBroadcastBaseX(), rainyBroadcastSlotY(i));
        hud.alpha = 0;
        hud.sort = 9999;
        hud.foreground = true;
        hud.archived = false;
        hud.hideWhenInMenu = false;
        hud.color = (1.0, 1.0, 1.0);
        hud.glowColor = (0.0, 0.0, 0.0);
        hud.glowAlpha = 0;
        hud set_text("");
        self.rainyBroadcastSlotHuds[i] = hud;
    }
}
rainyAddBroadcastFeedEntry(msg)
{
    self endon("disconnect");
    self endon("rainy_broadcast_shutdown");
    level endon("rainy_shutdown");

    if (isDefined(level.rainyLevelShuttingDown) && level.rainyLevelShuttingDown)
        return;

    self rainyEnsureBroadcastSlots();
    self rainyCleanExpiredBroadcastEntries();

    if (!isDefined(self.rainyShotFeedMsgs))
        self.rainyShotFeedMsgs = [];
    if (!isDefined(self.rainyShotFeedTimes))
        self.rainyShotFeedTimes = [];

    maxMsgs = rainyBroadcastMaxMessages();
    oldMsgs = self.rainyShotFeedMsgs;
    oldTimes = self.rainyShotFeedTimes;

    newMsgs = [];
    newTimes = [];

    // Newest entry always appears in the bottom row. Existing entries shift upward
    // by slot assignment only; the text HUDs themselves remain fixed in place.
    newMsgs[0] = msg;
    newTimes[0] = getTime();

    writeIndex = 1;
    for (i = 0; i < oldMsgs.size && writeIndex < maxMsgs; i++)
    {
        if (!isDefined(oldMsgs[i]))
            continue;

        newMsgs[writeIndex] = oldMsgs[i];
        newTimes[writeIndex] = oldTimes[i];
        writeIndex++;
    }

    self.rainyShotFeedMsgs = newMsgs;
    self.rainyShotFeedTimes = newTimes;

    self rainyRenderBroadcastSlots();

    if (rainyGameIsEnding())
        self rainyStartPostGameBroadcastRefresh();

    if (!isDefined(self.rainyBroadcastFadeLoopRunning) || !self.rainyBroadcastFadeLoopRunning)
    {
        self.rainyBroadcastFadeLoopRunning = true;
        self thread rainyBroadcastFadeLoop();
    }
}
rainyCleanExpiredBroadcastEntries()
{
    if (!isDefined(self.rainyShotFeedMsgs) || !isDefined(self.rainyShotFeedTimes))
        return;

    now = getTime();
    maxAge = rainyBroadcastHoldTimeMs() + rainyBroadcastFadeTimeMs();

    cleanMsgs = [];
    cleanTimes = [];
    writeIndex = 0;

    for (i = 0; i < self.rainyShotFeedMsgs.size; i++)
    {
        if (!isDefined(self.rainyShotFeedMsgs[i]))
            continue;
        if (!isDefined(self.rainyShotFeedTimes[i]))
            continue;

        age = now - self.rainyShotFeedTimes[i];
        if (age >= maxAge)
            continue;

        cleanMsgs[writeIndex] = self.rainyShotFeedMsgs[i];
        cleanTimes[writeIndex] = self.rainyShotFeedTimes[i];
        writeIndex++;
    }

    self.rainyShotFeedMsgs = cleanMsgs;
    self.rainyShotFeedTimes = cleanTimes;
}
rainyBroadcastAlphaForEntry(entryTime)
{
    if (!isDefined(entryTime))
        return 0;

    age = getTime() - entryTime;
    holdMs = rainyBroadcastHoldTimeMs();
    fadeMs = rainyBroadcastFadeTimeMs();

    if (age < holdMs)
        return 1.0;

    if (age >= holdMs + fadeMs)
        return 0;

    fadeAge = age - holdMs;
    alpha = 1.0 - ((fadeAge * 1.0) / fadeMs);

    if (alpha < 0)
        alpha = 0;
    if (alpha > 1)
        alpha = 1;

    return alpha;
}
rainyRenderBroadcastSlots()
{
    if (isDefined(level.rainyLevelShuttingDown) && level.rainyLevelShuttingDown)
        return;

    self rainyEnsureBroadcastSlots();
    if (!isDefined(self.rainyBroadcastSlotHuds))
        return;

    maxMsgs = rainyBroadcastMaxMessages();

    for (i = 0; i < maxMsgs; i++)
    {
        hud = self.rainyBroadcastSlotHuds[i];
        if (!isDefined(hud))
            continue;

        // Position is set once at creation in rainyEnsureBroadcastSlots and never
        // touched again here - only text/alpha change per refresh, same pattern
        // already used by rainyRenderMsgStackSlots. setPoint's coordinates here
        // (rainyBroadcastBaseX/rainyBroadcastSlotY) are fixed constants that never
        // change at runtime, so re-issuing this every 0.05s tick was pure redundant
        // work, not a correctness fix - removed per Stability Review.

        if (isDefined(self.rainyShotFeedMsgs) && isDefined(self.rainyShotFeedMsgs[i]))
        {
            alpha = 1.0;
            if (isDefined(self.rainyShotFeedTimes) && isDefined(self.rainyShotFeedTimes[i]))
                alpha = rainyBroadcastAlphaForEntry(self.rainyShotFeedTimes[i]);

            hud set_text(self.rainyShotFeedMsgs[i]);
            hud.alpha = alpha;
            hud.glowAlpha = 0.95 * alpha;
        }
        else
        {
            hud set_text("");
            hud.alpha = 0;
            hud.glowAlpha = 0;
        }
    }
}
rainyBroadcastFadeLoop()
{
    self endon("disconnect");
    self endon("rainy_broadcast_shutdown");
    level endon("game_ended");
    level endon("rainy_shutdown");

    while (true)
    {
        self rainyCleanExpiredBroadcastEntries();
        self rainyRenderBroadcastSlots();

        if (!isDefined(self.rainyShotFeedMsgs) || self.rainyShotFeedMsgs.size <= 0)
        {
            self.rainyBroadcastFadeLoopRunning = false;
            return;
        }

        wait 0.05;
    }
}
rainyClosestPointOnSegment(point, segStart, segEnd)
{
    // Manual point-to-segment projection using only basic vector component math
    // (no reliance on any unverified built-in like a "distance to line" helper).
    seg = (segEnd[0] - segStart[0], segEnd[1] - segStart[1], segEnd[2] - segStart[2]);
    segLenSq = (seg[0] * seg[0]) + (seg[1] * seg[1]) + (seg[2] * seg[2]);
    if (segLenSq <= 0)
        return segStart;
    toPoint = (point[0] - segStart[0], point[1] - segStart[1], point[2] - segStart[2]);
    t = ((toPoint[0] * seg[0]) + (toPoint[1] * seg[1]) + (toPoint[2] * seg[2])) / segLenSq;
    if (t < 0) t = 0;
    if (t > 1) t = 1;
    closest = (segStart[0] + seg[0] * t, segStart[1] + seg[1] * t, segStart[2] + seg[2] * t);
    return closest;
}
/*
    "Almost hit" used to measure distance from the bullet's path to ONLY the target's
    head tag. That meant a shot grazing close to someone's chest, legs, or an
    outstretched arm scored as "far" (no almost-hit) purely because it wasn't near the
    head specifically, while a shot that was merely somewhat-near the head - even with
    the rest of the body nowhere close - scored as "close." This is exactly the
    inconsistency where one shot near a certain body part triggers the message and
    another shot equally near a different body part doesn't.

    Fix: approximate the target's vertical body extent as a 3-point line (head, a
    computed mid-body point, and the entity's own origin - which in this engine sits at
    ground level under the player, i.e. effectively the feet) instead of head alone.
    For each sample point, reuse the existing rainyClosestPointOnSegment to find that
    point's distance to the bullet's path, then return the SMALLEST of the three. This
    doesn't touch the 45-unit threshold itself - it only changes what that threshold is
    measured against, so a shot now has to be close to ANY representative point along
    the body to register, matching real-world intuition of "how close did this come to
    hitting them" rather than "how close did this come to hitting their head."

    Mid-body uses the midpoint between head and origin rather than a guessed spine/chest
    tag name, since head and origin are both guaranteed to exist on any player entity in
    every stance (standing/crouch/prone), where a specific spine tag's exact name and
    behavior across stances is less certain to verify without live testing.
*/
rainyClosestDistanceToBody(target, traceStart, traceEnd)
{
    head = target getTagOrigin("j_head");
    feet = target.origin;
    mid = (
        (head[0] + feet[0]) / 2,
        (head[1] + feet[1]) / 2,
        (head[2] + feet[2]) / 2
    );

    nearestToHead = rainyClosestPointOnSegment(head, traceStart, traceEnd);
    nearestToMid = rainyClosestPointOnSegment(mid, traceStart, traceEnd);
    nearestToFeet = rainyClosestPointOnSegment(feet, traceStart, traceEnd);

    dHead = distance(head, nearestToHead);
    dMid = distance(mid, nearestToMid);
    dFeet = distance(feet, nearestToFeet);

    best = dHead;
    if (dMid < best)
        best = dMid;
    if (dFeet < best)
        best = dFeet;
    return best;
}
rainySniperShotWatcher()
{
    // Tracks no-scope sniper shots for the almost-hit trace system. Direct hits are
    // classified again inside rainyPlayerDamageHook using the damage callback weapon
    // plus the live ADS state, because damage can land in the same frame as
    // weapon_fired and beat this watcher to setting rainyLastShotWasNoScope.
    self endon("disconnect");
    level endon("game_ended");
    level endon("rainy_shutdown");
    // self.adsHeldTicks turned out to be an unused leftover variable from elsewhere in
    // the menu - it's initialized to 0 once and never updated anywhere, so checking it
    // here always read 0 and let every shot through as a "no-scope" regardless of
    // whether the scope was actually up. Tracking real ADS-held time locally instead:
    // adsButtonPressed() is sampled continuously, and rainyAdsDownSince records when it
    // last went from not-pressed to pressed so we can measure how long it was held by
    // the moment the shot fires.
    self.rainyAdsDownSince = 0;
    self thread rainyAdsHoldTracker();
    for (;;)
    {
        self waittill("weapon_fired");
        weapon = self getCurrentWeapon();
        if (!rainyIsSniperRifle(weapon))
        {
            self.rainyLastShotWasNoScope = false;
            continue;
        }
        // A true no-scope (including a fast quickscope tap) means ADS was either not
        // pressed at all at the moment of firing, or had only just been pressed a brief
        // instant before - not held long enough to actually be scoped in. 150ms is
        // generous enough to allow a real quickscope tap through while still excluding
        // a deliberate hold-then-fire hardscope.
        adsIsDown = self adsButtonPressed();
        heldMs = 0;
        if (adsIsDown && self.rainyAdsDownSince > 0)
            heldMs = getTime() - self.rainyAdsDownSince;
        if (adsIsDown && heldMs > 150)
        {
            self.rainyLastShotWasNoScope = false;
            continue;
        }
        if (!isDefined(self.rainyNoScopeShotId))
            self.rainyNoScopeShotId = 0;
        self.rainyNoScopeShotId++;
        self.rainyLastShotWasNoScope = true;
        self.rainyLastShotWeapon = weapon;
        self.rainyLastShotTime = getTime();
        self.rainyLastShotId = self.rainyNoScopeShotId;
        self thread rainyAlmostHitCheck(weapon, self.rainyLastShotId, self.rainyLastShotTime);
    }
}
rainyAdsHoldTracker()
{
    // Samples adsButtonPressed() every tick and records the timestamp of the rising
    // edge (not-pressed -> pressed) into self.rainyAdsDownSince, so the watcher above
    // can compute how long ADS has actually been held by the time a shot fires.
    self endon("disconnect");
    level endon("game_ended");
    level endon("rainy_shutdown");
    wasDown = false;
    for (;;)
    {
        isDown = self adsButtonPressed();
        if (isDown && !wasDown)
            self.rainyAdsDownSince = getTime();
        else if (!isDown)
            self.rainyAdsDownSince = 0;
        wasDown = isDown;
        wait 0.05;
    }
}
rainyShotAlreadyRegisteredDirectHit(shooter, shotId, shotTime)
{
    if (!isDefined(shooter))
        return false;

    if (isDefined(shotId) && isDefined(shooter.rainyLastDirectHitShotId) && shooter.rainyLastDirectHitShotId == shotId)
        return true;

    if (isDefined(shotTime) && isDefined(shooter.rainyLastDirectHitTime))
    {
        if (shooter.rainyLastDirectHitTime >= (shotTime - 150) && shooter.rainyLastDirectHitTime <= (getTime() + 50))
            return true;
    }

    return false;
}
rainyAlmostHitCheck(weapon, shotId, shotTime)
{
    self endon("disconnect");
    level endon("rainy_shutdown");

    // Runs a bullet trace for a no-scope sniper shot that was just fired. If the trace
    // doesn't directly hit another player/bot (a real hit is handled separately by the
    // damage hook), this looks for the closest other player/bot near the trace line and,
    // if close enough, reports it as an "almost hit". Hitmarkers (shots that DID connect
    // but didn't kill) are reported from the damage hook instead, so this only ever
    // covers clean misses - no double reporting of the same shot.
    shooter = self;
    if (!isDefined(shooter.almostHitsOn) || !shooter.almostHitsOn)
    {
        return;
    }
    eyePos = shooter getTagOrigin("j_head");
    forward = anglesToForward(shooter getPlayerAngles());
    endPos = (eyePos[0] + forward[0] * 100000, eyePos[1] + forward[1] * 100000, eyePos[2] + forward[2] * 100000);
    trace = bulletTrace(eyePos, endPos, false, shooter);
    if (!isDefined(trace) || !isDefined(trace["position"]))
    {
        return;
    }
    hitEnt = trace["entity"];
    if (isDefined(hitEnt) && rainyEntityIsTrackedPlayer(hitEnt))
    {
        return;   // direct hit on a player/bot - the damage hook already handles this
    }
    tracePos = trace["position"];
    closestTarget = undefined;
    closestDist = 999999;
    if (!isDefined(level.players))
    {
        return;
    }
    for (i = 0; i < level.players.size; i++)
    {
        p = level.players[i];
        if (!isDefined(p)) continue;
        if (p == shooter) continue;
        if (!isAlive(p)) continue;
        // Skip teammates entirely unless Friendly Fire is on - matches the same
        // same-team check already used for forcing friendly-fire damage, so Almost
        // Hits only ever fires on teammates when FF would actually let a real hit
        // count too. Gated to non-FFA gametypes only: MW2 commonly assigns every
        // player the same internal team value in FFA (dm), so without this check
        // every other player in FFA would incorrectly read as a "teammate" and
        // Almost Hits would stop firing on anyone at all.
        if (getDvar("g_gametype") != "dm" && (!isDefined(level.rainyFriendlyFire) || !level.rainyFriendlyFire) && rainyPlayersAreSameRealTeam(shooter, p))
            continue;
        d = rainyClosestDistanceToBody(p, eyePos, tracePos);
        if (d < closestDist)
        {
            closestDist = d;
            closestTarget = p;
        }
    }
    if (!isDefined(closestTarget))
    {
        return;
    }
    // "Almost hit" threshold: within ~45 game units of the bullet's path but didn't
    // actually register a hit. Narrowed back down from 60 toward the original 40 per
    // request - tune further if it still feels too generous/strict. closestDist now
    // comes from rainyClosestDistanceToBody (head/mid/feet), not the head alone, so
    // this same 45-unit number now applies consistently across the whole body instead
    // of only being meaningful for shots that happened to pass near the head.
    if (closestDist > 45)
    {
        return;
    }
    // Give the damage callback a tiny window to mark this shot as a real direct hit.
    // Without this, a hitmarker can race the almost-hit trace and both messages print.
    wait 0.1;
    if (!isDefined(shooter.almostHitsOn) || !shooter.almostHitsOn)
        return;
    if (rainyShotAlreadyRegisteredDirectHit(shooter, shotId, shotTime))
        return;
    if (!isDefined(closestTarget) || !isAlive(closestTarget))
        return;

    shooterDist = distance(shooter.origin, closestTarget.origin);
    meters = int(shooterDist / 39.37);
    msg = "^1" + shooter.name + " ^7almost hit ^1" + closestTarget.name + " ^7from ^5" + meters + " meters^7 away!";
    rainyBroadcastMessage(msg);
}
rainyApplyFriendlyFireState(enabled)
{
    if (enabled)
    {
        setDvar("scr_team_fftype", "1");
        level.friendlyfire = 1;
        level.friendlyFire = 1;
        level.friendlyFireType = 1;
    }
    else
    {
        setDvar("scr_team_fftype", "0");
        level.friendlyfire = 0;
        level.friendlyFire = 0;
        level.friendlyFireType = 0;
    }
}
rainyGetPlayerTeam(player)
{
    if (!isDefined(player))
        return "";

    // MW2's own damage script determines friendly fire from the entity .team field,
    // so prefer that first. Fall back to pers/sessionteam for bots or edge cases.
    if (isDefined(player.team))
        return player.team;
    if (isDefined(player.pers) && isDefined(player.pers["team"]))
        return player.pers["team"];
    if (isDefined(player.sessionteam))
        return player.sessionteam;
    return "";
}
rainyPlayersAreSameRealTeam(playerOne, playerTwo)
{
    teamOne = rainyGetPlayerTeam(playerOne);
    teamTwo = rainyGetPlayerTeam(playerTwo);
    if (teamOne == "" || teamTwo == "")
        return false;
    if (teamOne == "none" || teamOne == "free" || teamOne == "spectator")
        return false;
    if (teamTwo == "none" || teamTwo == "free" || teamTwo == "spectator")
        return false;
    return (teamOne == teamTwo);
}
rainyShouldForceFriendlyFireDamage(victim, attacker, damage)
{
    if (!isDefined(level.rainyFriendlyFire) || !level.rainyFriendlyFire)
        return false;
    if (!isDefined(victim) || !isDefined(attacker) || victim == attacker)
        return false;
    if (!isDefined(damage) || damage <= 0)
        return false;
    if (!rainyEntityIsTrackedPlayer(victim) || !rainyEntityIsTrackedPlayer(attacker))
        return false;
    return rainyPlayersAreSameRealTeam(victim, attacker);
}
rainyForceFriendlyFireDamage(eInflictor, eAttacker, iDamage, iDFlags, sMeansOfDeath, sWeapon, vPoint, vDir, sHitLoc, psOffsetTime)
{
    // Force full same-team damage through the normal gametype damage path.
    // Runtime dvar toggles alone do not always update level.friendlyfire mid-match,
    // so set the level value immediately before calling the original damage callback.
    if (!isDefined(iDamage) || iDamage < 1)
        iDamage = 1;

    oldHealth = undefined;
    if (isDefined(self.health))
        oldHealth = self.health;

    oldFriendlyFire = undefined;
    oldFriendlyFireAlt = undefined;
    oldFriendlyFireType = undefined;

    if (isDefined(level.friendlyfire))
        oldFriendlyFire = level.friendlyfire;
    if (isDefined(level.friendlyFire))
        oldFriendlyFireAlt = level.friendlyFire;
    if (isDefined(level.friendlyFireType))
        oldFriendlyFireType = level.friendlyFireType;

    level.friendlyfire = 1;
    level.friendlyFire = 1;
    level.friendlyFireType = 1;
    setDvar("scr_team_fftype", "1");

    self [[level.rainyOrigPlayerDamage]](eInflictor, eAttacker, iDamage, iDFlags, sMeansOfDeath, sWeapon, vPoint, vDir, sHitLoc, psOffsetTime);

    // Safety fallback ONLY for the rare case where the stock callback's own
    // friendly-fire gate still silently swallowed the damage (e.g. a stale
    // per-client FF flag) despite level.friendlyfire/scr_team_fftype being set
    // above. This deliberately does NOT call finishPlayerDamage again here: the
    // stock callback just called above already calls finishPlayerDamage
    // internally as the normal final step of ITS OWN pipeline once its internal
    // FF check passes (which it should, given the override above) - manually
    // calling it a second time would double-invoke a function that can trigger
    // death/kill processing for the same hit, risking corrupted state or a crash
    // on a lethal trade between teammates. A direct health write is simple,
    // can't double-trigger anything, and still delivers the intended "this hit
    // visibly landed" feedback.
    if (isAlive(self) && isDefined(oldHealth) && isDefined(self.health) && self.health >= oldHealth)
    {
        newHealth = oldHealth - iDamage;
        if (newHealth < 1)
            newHealth = 1;
        self.health = newHealth;
    }

    if (!isDefined(level.rainyFriendlyFire) || !level.rainyFriendlyFire)
    {
        if (isDefined(oldFriendlyFire))
            level.friendlyfire = oldFriendlyFire;
        if (isDefined(oldFriendlyFireAlt))
            level.friendlyFire = oldFriendlyFireAlt;
        if (isDefined(oldFriendlyFireType))
            level.friendlyFireType = oldFriendlyFireType;
    }
}
rainyDamageWasNoScopeSniper(eAttacker, sWeapon, sMeansOfDeath)
{
    // Direct-hit trickshot detection should only qualify real sniper bullet damage.
    // The old fallback used getCurrentWeapon(), which meant a knife hit while holding
    // a sniper could be misread as a no-scope sniper hit. Keep the weapon_fired race
    // protection, but never allow melee/knife/non-bullet damage to fall back to the
    // currently held sniper.
    if (!isDefined(eAttacker))
        return false;

    if (isDefined(sMeansOfDeath) && sMeansOfDeath != "MOD_RIFLE_BULLET" && sMeansOfDeath != "MOD_HEAD_SHOT")
        return false;

    weaponToCheck = undefined;

    if (isDefined(sWeapon) && sWeapon != "")
    {
        if (!rainyIsSniperRifle(sWeapon))
            return false;

        weaponToCheck = sWeapon;
    }
    else
    {
        if (isDefined(eAttacker.rainyLastShotWeapon) && isDefined(eAttacker.rainyLastShotTime) && getTime() - eAttacker.rainyLastShotTime <= 500)
            weaponToCheck = eAttacker.rainyLastShotWeapon;
        else
            return false;
    }

    if (!rainyIsSniperRifle(weaponToCheck))
        return false;

    adsIsDown = eAttacker adsButtonPressed();
    heldMs = 0;
    if (adsIsDown && isDefined(eAttacker.rainyAdsDownSince) && eAttacker.rainyAdsDownSince > 0)
        heldMs = getTime() - eAttacker.rainyAdsDownSince;
    if (adsIsDown && heldMs > 150)
        return false;
    return true;
}
rainyDamageAllowedInTrickshotOnly(eAttacker, sWeapon, sMeansOfDeath)
{
    if (rainyDamageWasNoScopeSniper(eAttacker, sWeapon, sMeansOfDeath))
        return true;
    if (rainyDamageWasAllowedTacticalGrenade(sWeapon))
        return true;
    if (rainyDamageWasAllowedThrowingKnife(sWeapon, sMeansOfDeath))
        return true;
    return false;
}

rainyDamageWasAllowedTacticalGrenade(sWeapon)
{
    if (!isDefined(sWeapon) || sWeapon == "")
        return false;
    if (sWeapon == "flash_grenade_mp" || sWeapon == "concussion_grenade_mp" || sWeapon == "stun_grenade_mp")
        return true;
    if (isSubStr(sWeapon, "flash") || isSubStr(sWeapon, "concussion") || isSubStr(sWeapon, "stun"))
        return true;
    return false;
}

rainyDamageWasAllowedThrowingKnife(sWeapon, sMeansOfDeath)
{
    // Same issubstr() approach as rainyIsSniperRifle: match against the raw weapon
    // name so prefix/suffix variants (e.g. "fire_weapon_throwingknife_mp") still hit.
    // Fall back to the means-of-death string in case sWeapon ever comes back empty
    // on a throwing knife hit.
    if (isDefined(sWeapon) && sWeapon != "" && issubstr(sWeapon, "throwingknife"))
        return true;
    if (isDefined(sMeansOfDeath) && sMeansOfDeath == "MOD_THROWING_KNIFE")
        return true;
    return false;
}

rainyReportTrickshotHitAfterDamage(victim, shotMeters, attackerName, victimName)
{
    // Wait one tiny slice so the original damage callback can actually apply the hit.
    // Then decide based on the real post-damage state instead of guessing from
    // iDamage >= self.health before perks, bot scripts, health scaling, or death logic
    // have finished.
    // Important: this thread must survive the normal game_ended notify. The final kill
    // can trigger stock endgame before this 0.05s wait finishes, and killing this thread
    // there is exactly what made final Trickshot Distance messages disappear.
    self endon("disconnect");
    level endon("rainy_shutdown");
    wait 0.05;
    if (!isDefined(victim))
        return;
    if (!isAlive(victim))
    {
        if (isDefined(self.trickshotDistanceOn) && self.trickshotDistanceOn)
        {
            msg = "^1" + attackerName + " ^7just hit ^1" + victimName + " ^7from ^5" + shotMeters + " meters^7 away!";
            rainyBroadcastMessage(msg);
        }
    }
    else
    {
        if (isDefined(self.almostHitsOn) && self.almostHitsOn)
        {
            msg = "^1" + attackerName + " ^7just hitmarkered ^1" + victimName + " ^7from ^5" + shotMeters + " meters^7 away!";
            rainyBroadcastMessage(msg);
        }
    }
}
rainyPlayerDamageHook(eInflictor, eAttacker, iDamage, iDFlags, sMeansOfDeath, sWeapon, vPoint, vDir, sHitLoc, psOffsetTime)
{
    if (isDefined(level.rainyLevelShuttingDown) && level.rainyLevelShuttingDown)
    {
        self [[level.rainyOrigPlayerDamage]](eInflictor, eAttacker, iDamage, iDFlags, sMeansOfDeath, sWeapon, vPoint, vDir, sHitLoc, psOffsetTime);
        return;
    }

    // Per-victim killcam control for the menu holder. Keep the stock/global killcam
    // gate enabled, then suppress only THIS victim when the host has Killcams OFF.
    // If the host toggles ON, explicitly clear cancelKillcam before the stock death
    // flow reaches its later killcam decision.
    if (isDefined(self.rainyKillcamsEnabled))
    {
        rainyEnsureGlobalKillcamAvailable();
        if (self.rainyKillcamsEnabled)
            self.cancelKillcam = false;
        else
            self.cancelKillcam = true;
    }

    // No-fall-damage at the script level. The bg_fallDamage dvars are cheat-protected
    // and don't reliably apply, and landing on props like the mattresses on Underpass
    // and Afghan deals damage through this callback as a fall/crush/impact death type.
    // Ignore those entirely so the player never takes environmental landing damage.
    if (isDefined(sMeansOfDeath) && (sMeansOfDeath == "MOD_FALLING" || sMeansOfDeath == "MOD_CRUSH" || sMeansOfDeath == "MOD_IMPACT"))
        return;

    // Lobby-wide Trickshot Damage Only: when enabled, only direct no-scope sniper
    // bullet damage, tactical grenade effects from stuns/flashes, and throwing knife
    // hits are allowed. Everything else (melee knife, explosives, scoped shots,
    // non-snipers, etc.) is ignored.
    if (isDefined(level.trickshotDamageOnly) && level.trickshotDamageOnly && iDamage > 0)
    {
        if (!rainyDamageAllowedInTrickshotOnly(eAttacker, sWeapon, sMeansOfDeath))
            return;
    }

    if (isDefined(level.healthDamageMult) && level.healthDamageMult != 1.0 && iDamage > 0 && !(isDefined(self.godMode) && self.godMode))
    {
        iDamage = int(iDamage * level.healthDamageMult);
        if (iDamage < 1)
            iDamage = 1;
    }
    // Trickshot Distance / Almost Hits (hitmarker case): direct-hit detection now uses
    // the damage callback weapon and ADS state instead of only trusting the
    // weapon_fired watcher flag. That avoids the race where the hit lands before
    // rainyLastShotWasNoScope is set.
    //
    // Also gated against teammates unless Friendly Fire is on (in actual team modes -
    // see the g_gametype != "dm" check, same reasoning as Almost Hits' own version of
    // this guard: FFA commonly assigns everyone the same internal team value, so this
    // check must never apply there). Both the Hitmarker and Trickshot Distance
    // messages come from this same trigger point (see rainyReportTrickshotHitAfterDamage
    // below), so this one guard covers both at once.
    if (isDefined(eAttacker) && rainyEntityIsTrackedPlayer(eAttacker) && eAttacker != self && iDamage > 0 && rainyDamageWasNoScopeSniper(eAttacker, sWeapon, sMeansOfDeath)
        && (getDvar("g_gametype") == "dm" || (isDefined(level.rainyFriendlyFire) && level.rainyFriendlyFire) || !rainyPlayersAreSameRealTeam(eAttacker, self)))
    {
        nowTime = getTime();
        eAttacker.rainyLastDirectHitTime = nowTime;
        if (isDefined(eAttacker.rainyLastShotId) && isDefined(eAttacker.rainyLastShotTime) && nowTime - eAttacker.rainyLastShotTime <= 600)
            eAttacker.rainyLastDirectHitShotId = eAttacker.rainyLastShotId;

        shouldReport = true;
        if (isDefined(eAttacker.rainyLastTSDVictim) && eAttacker.rainyLastTSDVictim == self && isDefined(eAttacker.rainyLastTSDTime) && nowTime - eAttacker.rainyLastTSDTime < 200)
            shouldReport = false;
        if (shouldReport)
        {
            eAttacker.rainyLastTSDVictim = self;
            eAttacker.rainyLastTSDTime = nowTime;
            shotDist = distance(eAttacker.origin, self.origin);
            shotMeters = int(shotDist / 39.37);
            eAttacker.rainyLastShotWasNoScope = false;
            eAttacker thread rainyReportTrickshotHitAfterDamage(self, shotMeters, eAttacker.name, self.name);
        }
    }
    // When this hit will kill the victim, take control of the weapon drop. Engine
    // death-drops are spawned by the engine with no script-findable classname or
    // handle, so their world models can't be removed when picked up via Take Ground
    // Weapon. By dropping the held gun ourselves while the victim is still alive we
    // get a real entity handle (exactly like the player's own menu drops, which DO
    // delete cleanly), then strip the rest of the inventory so the engine drops
    // nothing untracked on death.
    forceFriendlyFireDamage = rainyShouldForceFriendlyFireDamage(self, eAttacker, iDamage);
    if (isAlive(self) && iDamage > 0 && isDefined(self.health) && iDamage >= self.health && !(isDefined(self.godMode) && self.godMode))
        self rainyControlledDeathDrop();
    if (forceFriendlyFireDamage)
    {
        self rainyForceFriendlyFireDamage(eInflictor, eAttacker, iDamage, iDFlags, sMeansOfDeath, sWeapon, vPoint, vDir, sHitLoc, psOffsetTime);
        return;
    }
    self [[level.rainyOrigPlayerDamage]](eInflictor, eAttacker, iDamage, iDFlags, sMeansOfDeath, sWeapon, vPoint, vDir, sHitLoc, psOffsetTime);
}
healthLoop(targetHealth)
{
    level endon("game_ended");
    level endon("rainy_shutdown");
    level endon("stopHealthLoop");
    for (;;)
    {
        for (i = 0; i < level.players.size; i++)
        {
            p = level.players[i];
            if (isDefined(p) && isAlive(p))
            {
                if (p.maxhealth != targetHealth)
                {
                    p.maxhealth = targetHealth;
                    p.health = targetHealth;
                    p setClientDvar("hud_health_startpulse_critical", "0");
                    p setClientDvar("hud_health_startpulse_injured", "0");
                }
            }
        }
        wait 0.5;
    }
}
cyclePlayerFOV()
{
    if (!isDefined(self.rainyFovLevel))
        self.rainyFovLevel = 1;
    self.rainyFovLevel++;
    if (self.rainyFovLevel > 5)
        self.rainyFovLevel = 1;
    fov = "65";
    if (self.rainyFovLevel == 2) fov = "80";
    else if (self.rainyFovLevel == 3) fov = "90";
    else if (self.rainyFovLevel == 4) fov = "100";
    else if (self.rainyFovLevel == 5) fov = "110";
    if (fov == "65")
        self thread rainyShowRaisedMessage("^5FOV ^7[^565 ^7(Default)^7]");
    else
        self thread rainyShowRaisedMessage("^5FOV ^7[^5" + fov + "^7]");
    self thread rainyApplyFov();
    // Change FOV is host-only by engine limitation, not a script bug: cg_fov
    // is one of a handful of dvars IW4x will not push to a client from the
    // server (setClientDvar is a no-op for it on non-host players - confirmed
    // via direct testing), so it only ever actually moves for the host, who
    // is also the listen server. Other players can still set their own FOV
    // locally via the in-game console (/cg_fov <value>), which does work.
}
rainyApplyFov()
{
    self endon("disconnect");
    fov = "65";
    if (isDefined(self.rainyFovLevel))
    {
        if (self.rainyFovLevel == 2) fov = "80";
        else if (self.rainyFovLevel == 3) fov = "90";
        else if (self.rainyFovLevel == 4) fov = "100";
        else if (self.rainyFovLevel == 5) fov = "110";
    }
    // cg_fov is set via setDvar, which on a listen server only ever actually
    // takes effect for the host's own client. setClientDvar was tested and
    // confirmed not to move FOV for non-host players in this engine, so it's
    // intentionally not used here.
    // cg_fovScale must be 1.0 otherwise it multiplies the fov and makes the
    // value look wrong even when cg_fov is set correctly.
    setDvar("cg_fov", fov);
    self setClientDvar("cg_fovScale", "1.0");
}
rainyFovPersistLoop()
{
    self endon("disconnect");
    level endon("game_ended");
    level endon("rainy_shutdown");
    // cg_fov is a saved dvar that the client reverts to its config value on every
    // (re)spawn, so a one-time set wouldn't stick. Re-apply the chosen FOV each spawn.
    for (;;)
    {
        self waittill("spawned_player");
        if (isDefined(self.rainyFovLevel) && self.rainyFovLevel > 1)
        {
            wait 0.1;
            self thread rainyApplyFov();
        }
    }
}
rainyCamoPersistLoop()
{
    self endon("disconnect");
    level endon("game_ended");
    level endon("rainy_shutdown");
    // When the player switches to a different weapon, sync rainyCamoIndex to that
    // weapon's stored camo. This prevents a stale index from a different gun being
    // used the next time a canswap or attachment equip runs.
    for (;;)
    {
        self waittill("weapon_change");
        current = self getCurrentWeapon();
        if (!isDefined(current) || current == "none")
            continue;
        if (isDefined(self.rainyCamoByWeapon) && isDefined(self.rainyCamoByWeapon[current]))
            self.rainyCamoIndex = self.rainyCamoByWeapon[current];
    }
}
getRainySpeedMult()
{
    if (!isDefined(self.playerSpeedLevel))
        return 1;
    if (self.playerSpeedLevel == 2) return 2;
    if (self.playerSpeedLevel == 3) return 3;
    if (self.playerSpeedLevel == 4) return 4;
    if (self.playerSpeedLevel == 5) return 5;
    if (self.playerSpeedLevel == 6) return 10;
    return 1;
}
cyclePlayerSpeed()
{
    if (!isDefined(self.playerSpeedLevel))
        self.playerSpeedLevel = 1;
    self.playerSpeedLevel++;
    if (self.playerSpeedLevel > 6)
        self.playerSpeedLevel = 1;
    // Fun Mods - Speed now applies lobby-wide: setClientDvar is called on every
    // connected real player (bots excluded), not just self, so the whole lobby
    // moves at the same speed the host picks from the menu.
    speedVal = "190";
    if (self.playerSpeedLevel == 1)
    {
        speedVal = "190";
        self thread rainyShowRaisedMessage("^5Speed ^7[^51x ^7(Normal)^7]");
    }
    else if (self.playerSpeedLevel == 2)
    {
        speedVal = "380";
        self thread rainyShowRaisedMessage("^5Speed ^7[^52x^7]");
    }
    else if (self.playerSpeedLevel == 3)
    {
        speedVal = "570";
        self thread rainyShowRaisedMessage("^5Speed ^7[^53x^7]");
    }
    else if (self.playerSpeedLevel == 4)
    {
        speedVal = "760";
        self thread rainyShowRaisedMessage("^5Speed ^7[^54x^7]");
    }
    else if (self.playerSpeedLevel == 5)
    {
        speedVal = "950";
        self thread rainyShowRaisedMessage("^5Speed ^7[^55x^7]");
    }
    else if (self.playerSpeedLevel == 6)
    {
        speedVal = "1900";
        self thread rainyShowRaisedMessage("^5Speed ^7[^510x^7]");
    }
    if (!isDefined(level.players))
        return;
    for (i = 0; i < level.players.size; i++)
    {
        p = level.players[i];
        if (!isDefined(p)) continue;
        if (rainyIsBot(p)) continue;
        p setClientDvar("g_speed", speedVal);
    }
}
rainyOpenClientsMenu()
{
    rainyOpenClientsMenuPage(0);
}
rainyOpenClientsMenuPage(pageNum)
{
    // clientList holds ONLY real entities (host, players, bots) sorted in that order.
    // The "All Players" row is virtual: it always occupies slot 0 of page 0 and is
    // NOT stored in clientList (storing a string next to entities breaks comparisons).
    self.clientList = [];
    players = level.players;
    if (!isDefined(players))
        return;
    for (i = 0; i < players.size; i++)
    {
        p = players[i];
        if (!isDefined(p)) continue;
        if (p isHost()) self.clientList[self.clientList.size] = p;
    }
    for (i = 0; i < players.size; i++)
    {
        p = players[i];
        if (!isDefined(p)) continue;
        if (p isHost()) continue;
        if (rainyIsBot(p)) continue;
        self.clientList[self.clientList.size] = p;
    }
    for (i = 0; i < players.size; i++)
    {
        p = players[i];
        if (!isDefined(p)) continue;
        if (rainyIsBot(p)) self.clientList[self.clientList.size] = p;
    }
    // Total selectable rows across all pages = 1 (All Players) + every client.
    self.clientsPageSize = 8;
    totalRows = self.clientList.size + 1;   // +1 for the virtual All Players row
    totalPages = int((totalRows + self.clientsPageSize - 1) / self.clientsPageSize);
    if (totalPages < 1) totalPages = 1;
    if (pageNum < 0) pageNum = 0;
    if (pageNum >= totalPages) pageNum = totalPages - 1;
    self.clientsPage = pageNum;
    self.clientsTotalPages = totalPages;
    // How many ROWS appear on this page (rows = virtual All Players + clients).
    rowsBefore = pageNum * self.clientsPageSize;
    rowsThisPage = totalRows - rowsBefore;
    if (rowsThisPage > self.clientsPageSize) rowsThisPage = self.clientsPageSize;
    if (rowsThisPage < 0) rowsThisPage = 0;
    if (self.clientsTotalPages > 1)
    {
        self.clientsPageNavSlot = rowsThisPage;   // nav directly below the last row
        self.clientsMenuMax = self.clientsPageNavSlot;
    }
    else
    {
        self.clientsPageNavSlot = -1;
        self.clientsMenuMax = rowsThisPage - 1;
    }
    if (self.clientsMenuMax < 0) self.clientsMenuMax = 0;
    self.menuPage = "clients";
    self.menuIndex = 0;
    self updateMenuHud();
}
rainyClientRowToListIdx(rowIdx)
{
    // Convert a global ROW index (0 = All Players, 1 = first client, ...) into a
    // clientList index. Returns -1 for the All Players row.
    return rowIdx - 1;
}
rainyBuildClientsRender()
{
    if (!isDefined(self.clientList) || self.clientList.size == 0)
    {
        self.menuHud0 set_text("^7  No players found");
        return;
    }
    pageStart = self.clientsPage * self.clientsPageSize;
    for (slot = 0; slot < self.clientsPageSize; slot++)
    {
        rowColor = "^5";
        if (slot % 2 == 1)
            rowColor = "^7";
        globalRow = pageStart + slot;   // 0 = All Players, 1+ = clientList[globalRow-1]
        hud = undefined;
        if      (slot == 0) hud = self.menuHud0;
        else if (slot == 1) hud = self.menuHud1;
        else if (slot == 2) hud = self.menuHud2;
        else if (slot == 3) hud = self.menuHud3;
        else if (slot == 4) hud = self.menuHud4;
        else if (slot == 5) hud = self.menuHud5;
        else if (slot == 6) hud = self.menuHud6;
        else if (slot == 7) hud = self.menuHud7;
        if (!isDefined(hud)) continue;
        // Skip the page-nav slot here; it is drawn separately below.
        if (isDefined(self.clientsPageNavSlot) && self.clientsPageNavSlot >= 0
            && slot == self.clientsPageNavSlot)
            continue;
        // Row 0 (only on page 0) is the virtual "All Players" entry.
        if (globalRow == 0)
        {
            if (self.menuIndex == slot) hud set_text("   All Players >>");
            else                        hud set_text(rowColor + "  All Players >>");
            continue;
        }
        listIdx = globalRow - 1;
        if (listIdx >= self.clientList.size)
        {
            hud set_text("");
            continue;
        }
        p = self.clientList[listIdx];
        if (!isDefined(p))
            label = "[disconnected]";
        else if (p isHost())
            label = "[HOST] " + p.name;
        else if (rainyIsBot(p))
            label = "[BOT] " + p.name;
        else
            label = "[PLAYER] " + p.name;
        selected = (self.menuIndex == slot);
        if (selected) hud set_text("   " + label + " >>");
        else          hud set_text(rowColor + "  " + label + " >>");
    }
    // Page navigator (only shown when there are multiple pages).
    // It sits directly under the last client on the current page instead of always using slot 8.
    if (isDefined(self.clientsTotalPages) && self.clientsTotalPages > 1)
    {
        navSlot = self.clientsPageNavSlot;
        navColor = "^5";
        oppositeColor = "^7";
        if (navSlot % 2 == 1)
        {
            navColor = "^7";
            oppositeColor = "^5";
        }
        nextPage = self.clientsPage + 1;
        if (nextPage >= self.clientsTotalPages) nextPage = 0;
        nextNum = nextPage + 1;
        navHud = undefined;
        if      (navSlot == 0) navHud = self.menuHud0;
        else if (navSlot == 1) navHud = self.menuHud1;
        else if (navSlot == 2) navHud = self.menuHud2;
        else if (navSlot == 3) navHud = self.menuHud3;
        else if (navSlot == 4) navHud = self.menuHud4;
        else if (navSlot == 5) navHud = self.menuHud5;
        else if (navSlot == 6) navHud = self.menuHud6;
        else if (navSlot == 7) navHud = self.menuHud7;
        else if (navSlot == 8) navHud = self.menuHud8;
        if (isDefined(navHud))
        {
            if (nextPage == 0)
            {
                if (self.menuIndex == navSlot)
                    navHud set_text("   Page 1 <-");
                else
                    navHud set_text(navColor + "  Page 1 " + oppositeColor + "<-");
            }
            else
            {
                if (self.menuIndex == navSlot)
                    navHud set_text("   Page " + nextNum + " ->");
                else
                    navHud set_text(navColor + "  Page " + nextNum + " " + oppositeColor + "->");
            }
        }
    }
    else if (isDefined(self.menuHud8))
    {
        self.menuHud8 set_text("");
    }
}

rainyClientsMenuSelect()
{
    if (!isDefined(self.clientList))
        return;
    slot = self.menuIndex;
    // Page nav slot
    if (isDefined(self.clientsTotalPages) && self.clientsTotalPages > 1
        && isDefined(self.clientsPageNavSlot) && slot == self.clientsPageNavSlot)
    {
        nextPage = self.clientsPage + 1;
        if (nextPage >= self.clientsTotalPages) nextPage = 0;
        self rainyOpenClientsMenuPage(nextPage);
        return;
    }
    globalRow = self.clientsPage * self.clientsPageSize + slot;
    // Row 0 = virtual All Players entry
    if (globalRow == 0)
    {
        self.clientsMenuLastIdx = slot;
        self.menuPage = "allplayers";
        self.menuIndex = 0;
        self updateMenuHud();
        return;
    }
    listIdx = globalRow - 1;
    if (listIdx >= self.clientList.size)
        return;
    target = self.clientList[listIdx];
    if (!isDefined(target))
    {
        // Matches rainyBuildClientsRender's own slot%2 coloring rule for this list.
        if (self.menuIndex % 2 == 0)
            self thread rainyShowRaisedMessage("^5Player no longer in lobby");
        else
            self thread rainyShowRaisedMessage("^7Player no longer in lobby");
        return;
    }
    self.clientsMenuLastIdx = slot;
    self.menuPage = "clientsub_" + target getEntityNumber();
    self.clientSubTitle = target.name;
    self.clientSubTarget = target;
    self.menuIndex = 0;
    self updateMenuHud();
}
rainyKickClient()
{
    target = self.clientSubTarget;
    if (!isDefined(target))
    {
        self thread rainyShowRaisedMessage("^7Player no longer in lobby");
        return;
    }
    name = target.name;
    // Host cannot be kicked
    if (target isHost())
    {
        self thread rainyShowRaisedMessage("^7Cannot kick the host");
        return;
    }
    entNum = target getEntityNumber();
    // Both bots and real players are kicked via kick(entityNumber).
    // Bot Warfare uses the same call internally.
    kick(entNum, "EXE_PLAYERKICKED");
    self thread rainyShowRaisedMessage("^7Kicked " + name);
    // Return to the client list (rebuild since the player is gone)
    prevPage = 0;
    if (isDefined(self.clientsPage)) prevPage = self.clientsPage;
    self rainyOpenClientsMenuPage(prevPage);
}
rainyKillClient()
{
    target = self.clientSubTarget;
    if (!isDefined(target))
    {
        self thread rainyShowRaisedMessage("^5Player no longer in lobby");
        return;
    }
    // Note: the host CAN be killed from their individual Kill Player option.
    // (All Players > Kill All still skips the host - that guard lives in
    // rainyKillAllPlayers and is intentionally left in place.)
    name = target.name;
    if (isAlive(target))
        target suicide();
    self thread rainyShowRaisedMessage("^5Killed " + name);
}
rainyFreezeClient()
{
    target = self.clientSubTarget;
    if (!isDefined(target))
    {
        self thread rainyShowRaisedMessage("^7Player no longer in lobby");
        return;
    }
    if (target isHost())
    {
        self thread rainyShowRaisedMessage("^7Cannot freeze the host");
        return;
    }
    if (target isBot())
        target.rainyIgnoreGlobalBotFreeze = undefined;
    rainyFreezeEntity(target);
    self thread rainyShowRaisedMessage("^7Froze " + target.name);
}
rainyUnfreezeClient()
{
    target = self.clientSubTarget;
    if (!isDefined(target))
    {
        self thread rainyShowRaisedMessage("^5Player no longer in lobby");
        return;
    }
    rainyUnfreezeEntity(target);
    self thread rainyShowRaisedMessage("^5Unfroze " + target.name);
}
rainyComputeCrosshairSpot(forEnt)
{
    // Returns a ground-traced point at the caller's crosshair, suitable to teleport
    // an entity onto. forEnt is the entity that will be placed there (used as the
    // trace-ignore entity). Caller is 'self' (the menu user doing the aiming).
    eyePos = self getTagOrigin("j_head");
    forward = anglesToForward(self GetPlayerAngles());
    trace = bulletTrace(eyePos, eyePos + (forward * 1000000), false, self);
    if (isDefined(trace["fraction"]) && trace["fraction"] >= 1.0)
        center = self.origin + (forward * 256);    // aiming at sky: a point ahead
    else
        center = trace["position"] - (forward * 16); // just off the surface, not inside
    return center;
}
rainyTeleportEntityTo(target, spot, faceAngles)
{
    // Teleport a single bot OR player to 'spot'. The placement calls (SetOrigin /
    // SetVelocity / SetPlayerAngles) are identical for both. The bot-only extra is
    // clearing the AI path so it re-routes from the new spot (or stays put if frozen).
    if (!isDefined(target))
        return;
    target SetVelocity((0, 0, 0));
    target SetOrigin(spot);
    target SetPlayerAngles(faceAngles);
    if (target isBot())
    {
        botFrozen = false;
        if (isDefined(target.rainyFrozen) && target.rainyFrozen)
            botFrozen = true;
        if (isDefined(level.botsFrozen) && level.botsFrozen && !rainyBotIgnoresGlobalFreeze(target))
            botFrozen = true;
        if (botFrozen)
        {
            // Keep a frozen bot pinned at its new location.
            target.frozenOrigin = spot;
            target.frozenAngles = faceAngles;
            target.rainyFrozenOrigin = spot;
            target.rainyFrozenAngles = faceAngles;
        }
        else
        {
            target notify("kill_goal");
            if (isDefined(target.bot))
            {
                target.bot.next_wp = -1;
                target.bot.second_next_wp = -1;
                target.bot.last_next_wp = -1;
                target.bot.last_second_next_wp = -1;
            }
        }
    }
    else
    {
        // Player: if frozen, update the pinned position so the freeze loop holds it there.
        if (isDefined(target.rainyFrozen) && target.rainyFrozen)
        {
            target.rainyFrozenOrigin = spot;
            target.rainyFrozenAngles = faceAngles;
        }
    }
}
rainyTeleportClientToMe()
{
    self endon("disconnect");
    target = self.clientSubTarget;
    if (!isDefined(target))
    {
        self thread rainyShowRaisedMessage("^5Player no longer in lobby");
        return;
    }
    if (target isHost())
    {
        self thread rainyShowRaisedMessage("^5Cannot teleport the host");
        return;
    }
    // Land just beside the menu user on a ground-traced spot.
    ang = randomint(360);
    spot = self.origin + (cos(ang) * 24, sin(ang) * 24, 0);
    ground = physicstrace(spot + (0, 0, 48), spot + (0, 0, -80), false, target);
    if (isDefined(ground))
        spot = ground + (0, 0, 2);
    rainyTeleportEntityTo(target, spot, self.angles);
    self thread rainyShowRaisedMessage("^5Teleported " + target.name + " to you");
}
rainyTeleportClientToCrosshair()
{
    self endon("disconnect");
    target = self.clientSubTarget;
    if (!isDefined(target))
    {
        self thread rainyShowRaisedMessage("^7Player no longer in lobby");
        return;
    }
    if (target isHost())
    {
        self thread rainyShowRaisedMessage("^7Cannot teleport the host");
        return;
    }
    center = self rainyComputeCrosshairSpot(target);
    ground = physicstrace(center + (0, 0, 72), center + (0, 0, -160), false, target);
    spot = center;
    if (isDefined(ground))
        spot = ground + (0, 0, 2);
    rainyTeleportEntityTo(target, spot, self.angles);
    self thread rainyShowRaisedMessage("^7Teleported " + target.name + " to crosshair");
}
rainyToggleClientGodMode()
{
    target = self.clientSubTarget;
    if (!isDefined(target))
    {
        self thread rainyShowRaisedMessage("^5Player no longer in lobby");
        return;
    }
    if (rainyIsBot(target))
    {
        self thread rainyShowRaisedMessage("^5Not available for bots");
        return;
    }
    if (!isDefined(target.godMode))
        target.godMode = false;
    target.godMode = !target.godMode;
    if (target.godMode)
    {
        target.maxhealth = 999999;
        target.health = 999999;
        target notify("god_mode_restart");
        target thread godModeLoop();
        self thread rainyShowRaisedMessage("^5God Mode ^7[^5ON^7] - " + target.name);
    }
    else
    {
        target notify("god_mode_restart");
        target.maxhealth = 100;
        target.health = 100;
        self thread rainyShowRaisedMessage("^5God Mode ^7[^5OFF^7] - " + target.name);
    }
}
rainyToggleClientTsAimbot()
{
    target = self.clientSubTarget;
    if (!isDefined(target))
    {
        self thread rainyShowRaisedMessage("^5Player no longer in lobby");
        return;
    }
    if (rainyIsBot(target))
    {
        self thread rainyShowRaisedMessage("^5Not available for bots");
        return;
    }
    if (!isDefined(target.tsAimbotOn))
        target.tsAimbotOn = false;
    target.tsAimbotOn = !target.tsAimbotOn;
    target notify("stopTsAimbot");
    if (target.tsAimbotOn)
    {
        target thread tsAimbotLoop();
        self thread rainyShowRaisedMessage("^5TS Aimbot ^7[^5ON^7] - " + target.name);
    }
    else
    {
        self thread rainyShowRaisedMessage("^5TS Aimbot ^7[^5OFF^7] - " + target.name);
    }
}
rainyToggleClientAutoRefill()
{
    target = self.clientSubTarget;
    if (!isDefined(target))
    {
        self thread rainyShowRaisedMessage("^5Player no longer in lobby");
        return;
    }
    if (rainyIsBot(target))
    {
        self thread rainyShowRaisedMessage("^5Not available for bots");
        return;
    }
    if (!isDefined(target.rainyAutoRefillAmmo))
        target.rainyAutoRefillAmmo = false;
    target.rainyAutoRefillAmmo = !target.rainyAutoRefillAmmo;
    if (target.rainyAutoRefillAmmo)
    {
        // Top off immediately, then poll on the target exactly like the host version.
        target rainyAutoRefillTick();
        target thread rainyAutoRefillAmmoLoop();
        self thread rainyShowRaisedMessage("^5Auto Refill Ammo ^7[^5ON^7] - " + target.name);
    }
    else
    {
        target notify("stopAutoRefillAmmo");
        self thread rainyShowRaisedMessage("^5Auto Refill Ammo ^7[^5OFF^7] - " + target.name);
    }
}
rainyClientFastLast()
{
    // One-shot action (no toggle state). Sets the target's individual FFA score to
    // one below the score limit - identical effect to the lobby Fast Last FFA, just
    // applied to the selected player. FFA only, players only.
    target = self.clientSubTarget;
    if (!isDefined(target))
    {
        self thread rainyShowRaisedMessage("^7Player no longer in lobby");
        return;
    }
    if (rainyIsBot(target))
    {
        self thread rainyShowRaisedMessage("^7Not available for bots");
        return;
    }
    if (getDvar("g_gametype") != "dm")
    {
        self thread rainyShowRaisedMessage("^7Fast Last FFA only works in FFA");
        return;
    }
    scoreLimit = getDvarInt("scr_dm_scorelimit");
    if (scoreLimit <= 1)
        scoreLimit = 30;
    lastScore = scoreLimit - 1;
    if (lastScore < 1)
        lastScore = 29;
    target.pers["score"] = lastScore;
    target.pers["kills"] = lastScore;
    target.score = lastScore;
    target.kills = lastScore;
    self thread rainyShowRaisedMessage("^7Fast Last FFA: " + target.name + " at " + lastScore + " kills - pull up scoreboard to update");
}
/*
    Mirrors rainyClientFastLast but zeroes the target's individual FFA score back to
    0 instead of setting it near the score limit - the "undo" counterpart, kept on
    page 2 of the per-player submenu alongside Canswap Bind.
*/
rainyClientResetFFAScore()
{
    target = self.clientSubTarget;
    if (!isDefined(target))
    {
        self thread rainyShowRaisedMessage("^7Player no longer in lobby");
        return;
    }
    if (rainyIsBot(target))
    {
        self thread rainyShowRaisedMessage("^7Not available for bots");
        return;
    }
    if (getDvar("g_gametype") != "dm")
    {
        self thread rainyShowRaisedMessage("^7Reset FFA Score only works in FFA");
        return;
    }
    target.pers["score"] = 0;
    target.pers["kills"] = 0;
    target.score = 0;
    target.kills = 0;
    self thread rainyShowRaisedMessage("^7Reset FFA Score: " + target.name + " at 0 kills - pull up scoreboard to update");
}
rainyToggleClientCanswap()
{
    self endon("disconnect");
    target = self.clientSubTarget;
    if (!isDefined(target))
    {
        self thread rainyShowRaisedMessage("^5Player no longer in lobby");
        return;
    }
    if (rainyIsBot(target))
    {
        self thread rainyShowRaisedMessage("^5Not available for bots");
        return;
    }
    if (!isDefined(target.canswapBound) || !target.canswapBound)
    {
        target.canswapBound = true;
        target thread canswapBindMonitor();
        self thread rainyShowRaisedMessage("^5Canswap Bind ^7[^5ON^7] - " + target.name + " (Standing + Dpad Up)");
    }
    else
    {
        target.canswapBound = false;
        target notify("stop_canswap_bind");
        self thread rainyShowRaisedMessage("^5Canswap Bind ^7[^5OFF^7] - " + target.name);
    }
}
rainyTeleportAllToMe()
{
    self endon("disconnect");
    if (!isDefined(level.players))
    {
        self thread rainyShowRaisedMessage("^5No players found");
        return;
    }
    center = self.origin;
    count = 0;
    for (i = 0; i < level.players.size; i++)
    {
        p = level.players[i];
        if (!isDefined(p)) continue;
        if (p isHost()) continue;     // never teleport the host
        // Spread across a tight ring so entities don't stack on one identical origin.
        ang = randomint(360);
        rad = randomintrange(12, 44);
        spot = center + (cos(ang) * rad, sin(ang) * rad, 0);
        ground = physicstrace(spot + (0, 0, 48), spot + (0, 0, -80), false, p);
        if (isDefined(ground))
            spot = ground + (0, 0, 2);
        rainyTeleportEntityTo(p, spot, self.angles);
        count++;
    }
    self thread rainyShowRaisedMessage("^5Teleported " + count + " players to you");
}
rainyTeleportAllToCrosshair()
{
    self endon("disconnect");
    if (!isDefined(level.players))
    {
        self thread rainyShowRaisedMessage("^7No players found");
        return;
    }
    center = self rainyComputeCrosshairSpot(self);
    count = 0;
    for (i = 0; i < level.players.size; i++)
    {
        p = level.players[i];
        if (!isDefined(p)) continue;
        if (p isHost()) continue;
        ang = randomint(360);
        rad = randomintrange(12, 44);
        spot = center + (cos(ang) * rad, sin(ang) * rad, 0);
        ground = physicstrace(spot + (0, 0, 72), spot + (0, 0, -160), false, p);
        if (isDefined(ground))
            spot = ground + (0, 0, 2);
        rainyTeleportEntityTo(p, spot, self.angles);
        count++;
    }
    self thread rainyShowRaisedMessage("^7Teleported " + count + " players to crosshair");
}
/*
    All Players page 2 - Auto Refill Ammo: same effect as the individual per-player
    Auto Refill Ammo toggle, just applied to every connected real player (host
    included, bots excluded) in one action. level.rainyAllAutoRefill tracks the
    group toggle state shown in the menu, since this isn't any single entity's flag.
*/
rainyToggleAllAutoRefill()
{
    if (!isDefined(level.players))
    {
        self thread rainyShowRaisedMessage("^5No players found");
        return;
    }
    if (!isDefined(level.rainyAllAutoRefill))
        level.rainyAllAutoRefill = false;
    level.rainyAllAutoRefill = !level.rainyAllAutoRefill;
    count = 0;
    for (i = 0; i < level.players.size; i++)
    {
        p = level.players[i];
        if (!isDefined(p)) continue;
        if (rainyIsBot(p)) continue;
        if (level.rainyAllAutoRefill)
        {
            p.rainyAutoRefillAmmo = true;
            p rainyAutoRefillTick();
            p thread rainyAutoRefillAmmoLoop();
        }
        else
        {
            p.rainyAutoRefillAmmo = false;
            p notify("stopAutoRefillAmmo");
        }
        count++;
    }
    if (level.rainyAllAutoRefill)
        self thread rainyShowRaisedMessage("^5Auto Refill Ammo ^7[^5ON^7] - " + count + " players");
    else
        self thread rainyShowRaisedMessage("^5Auto Refill Ammo ^7[^5OFF^7] - " + count + " players");
}
/*
    All Players page 2 - Fast Last FFA: same effect as rainyClientFastLast, applied
    to every connected real player (host included, bots excluded) at once.
*/
rainyFastLastAllFFA()
{
    if (!isDefined(level.players))
    {
        self thread rainyShowRaisedMessage("^7No players found");
        return;
    }
    if (getDvar("g_gametype") != "dm")
    {
        self thread rainyShowRaisedMessage("^7Fast Last FFA only works in FFA");
        return;
    }
    scoreLimit = getDvarInt("scr_dm_scorelimit");
    if (scoreLimit <= 1)
        scoreLimit = 30;
    lastScore = scoreLimit - 1;
    if (lastScore < 1)
        lastScore = 29;
    count = 0;
    for (i = 0; i < level.players.size; i++)
    {
        p = level.players[i];
        if (!isDefined(p)) continue;
        if (rainyIsBot(p)) continue;
        p.pers["score"] = lastScore;
        p.pers["kills"] = lastScore;
        p.score = lastScore;
        p.kills = lastScore;
        count++;
    }
    self thread rainyShowRaisedMessage("^7Fast Last FFA: " + count + " players at " + lastScore + " kills - pull up scoreboard to update");
}
/*
    All Players page 2 - Reset FFA Score: mirrors rainyClientResetFFAScore, applied
    to every connected real player (host included, bots excluded) at once.
*/
rainyResetAllFFAScore()
{
    if (!isDefined(level.players))
    {
        self thread rainyShowRaisedMessage("^7No players found");
        return;
    }
    if (getDvar("g_gametype") != "dm")
    {
        self thread rainyShowRaisedMessage("^7Reset FFA Score only works in FFA");
        return;
    }
    count = 0;
    for (i = 0; i < level.players.size; i++)
    {
        p = level.players[i];
        if (!isDefined(p)) continue;
        if (rainyIsBot(p)) continue;
        p.pers["score"] = 0;
        p.pers["kills"] = 0;
        p.score = 0;
        p.kills = 0;
        count++;
    }
    self thread rainyShowRaisedMessage("^7Reset FFA Score: " + count + " players at 0 kills - pull up scoreboard to update");
}
/*
    All Players page 2 - Canswap Bind: same effect as rainyToggleClientCanswap,
    applied to every connected real player (host included, bots excluded) at once.
    level.rainyAllCanswap tracks the group toggle state shown in the menu.
*/
rainyToggleAllCanswap()
{
    if (!isDefined(level.players))
    {
        self thread rainyShowRaisedMessage("^5No players found");
        return;
    }
    if (!isDefined(level.rainyAllCanswap))
        level.rainyAllCanswap = false;
    level.rainyAllCanswap = !level.rainyAllCanswap;
    count = 0;
    for (i = 0; i < level.players.size; i++)
    {
        p = level.players[i];
        if (!isDefined(p)) continue;
        if (rainyIsBot(p)) continue;
        if (level.rainyAllCanswap)
        {
            p.canswapBound = true;
            p thread canswapBindMonitor();
        }
        else
        {
            p.canswapBound = false;
            p notify("stop_canswap_bind");
        }
        count++;
    }
    if (level.rainyAllCanswap)
        self thread rainyShowRaisedMessage("^5Canswap Bind ^7[^5ON^7] - " + count + " players (Standing + Dpad Up)");
    else
        self thread rainyShowRaisedMessage("^5Canswap Bind ^7[^5OFF^7] - " + count + " players");
}
/*
    All Players page 2 - God Mode: same effect as rainyToggleClientGodMode, applied
    to every connected real player (host included, bots excluded) at once.
    level.rainyAllGodMode tracks the group toggle state shown in the menu.
*/
rainyToggleAllGodMode()
{
    if (!isDefined(level.players))
    {
        self thread rainyShowRaisedMessage("^5No players found");
        return;
    }
    if (!isDefined(level.rainyAllGodMode))
        level.rainyAllGodMode = false;
    level.rainyAllGodMode = !level.rainyAllGodMode;
    count = 0;
    for (i = 0; i < level.players.size; i++)
    {
        p = level.players[i];
        if (!isDefined(p)) continue;
        if (rainyIsBot(p)) continue;
        p.godMode = level.rainyAllGodMode;
        if (level.rainyAllGodMode)
        {
            p.maxhealth = 999999;
            p.health = 999999;
            p notify("god_mode_restart");
            p thread godModeLoop();
        }
        else
        {
            p notify("god_mode_restart");
            p.maxhealth = 100;
            p.health = 100;
        }
        count++;
    }
    if (level.rainyAllGodMode)
        self thread rainyShowRaisedMessage("^5God Mode ^7[^5ON^7] - " + count + " players");
    else
        self thread rainyShowRaisedMessage("^5God Mode ^7[^5OFF^7] - " + count + " players");
}
rainyToggleAllTsAimbot()
{
    if (!isDefined(level.players))
    {
        self thread rainyShowRaisedMessage("^5No players found");
        return;
    }
    if (!isDefined(level.rainyAllTsAimbot))
        level.rainyAllTsAimbot = false;
    level.rainyAllTsAimbot = !level.rainyAllTsAimbot;
    count = 0;
    for (i = 0; i < level.players.size; i++)
    {
        p = level.players[i];
        if (!isDefined(p)) continue;
        if (rainyIsBot(p)) continue;
        p.tsAimbotOn = level.rainyAllTsAimbot;
        p notify("stopTsAimbot");
        if (level.rainyAllTsAimbot)
            p thread tsAimbotLoop();
        count++;
    }
    if (level.rainyAllTsAimbot)
        self thread rainyShowRaisedMessage("^5TS Aimbot ^7[^5ON^7] - " + count + " players");
    else
        self thread rainyShowRaisedMessage("^5TS Aimbot ^7[^5OFF^7] - " + count + " players");
}
/*
    Fun Mods - Visions: applies the same postfx vision the host just set on
    themselves to every other connected real player (bots excluded). Called right
    after each "self visionSetNakedForPlayer(...)" line in the visions select-handler
    so the whole lobby sees the same vision, not just the host. visionName == ""
    resets a player back to naked/no vision (used for None and as the reset step
    before every named vision).
*/
rainyApplyVisionToAllPlayers(visionName)
{
    if (!isDefined(level.players))
        return;
    for (i = 0; i < level.players.size; i++)
    {
        p = level.players[i];
        if (!isDefined(p)) continue;
        if (p == self) continue;
        if (rainyIsBot(p)) continue;
        p visionSetNakedForPlayer(visionName, 0.1);
    }
}
rainyApplyFullbrightToAllPlayers(state)
{
    // r_fullbright is a client-side render dvar (not server-authoritative),
    // so each real player needs it pushed individually via setClientDvar.
    // Bots are skipped - they don't render a viewport, so this would be a
    // no-op for them anyway.
    if (!isDefined(level.players))
        return;
    for (i = 0; i < level.players.size; i++)
    {
        p = level.players[i];
        if (!isDefined(p)) continue;
        if (p == self) continue;
        if (rainyIsBot(p)) continue;
        p setClientDvar("r_fullbright", state);
    }
}
rainyIsBot(player)
{
    if (!isDefined(player))
        return false;
    if (isDefined(player.pers["isBot"]) && player.pers["isBot"])
        return true;
    if (isDefined(player.pers["isBotWarfare"]) && player.pers["isBotWarfare"])
        return true;
    if (isSubStr(player getGuid() + "", "bot"))
        return true;
    return false;
}
toggleTrickshotDamageOnly()
{
    if (!isDefined(level.trickshotDamageOnly))
        level.trickshotDamageOnly = false;
    level.trickshotDamageOnly = !level.trickshotDamageOnly;
    if (level.trickshotDamageOnly)
        self thread rainyShowRaisedMessage("^5Trickshot Damage Only ^7[^5ON^7]");
    else
        self thread rainyShowRaisedMessage("^5Trickshot Damage Only ^7[^5OFF^7]");
}
toggleFriendlyFire()
{
    if (!isDefined(level.rainyFriendlyFire))
        level.rainyFriendlyFire = false;
    level.rainyFriendlyFire = !level.rainyFriendlyFire;
    rainyApplyFriendlyFireState(level.rainyFriendlyFire);
    if (level.rainyFriendlyFire)
        self thread rainyShowRaisedMessage("^5Friendly Fire ^7[^5ON^7]");
    else
        self thread rainyShowRaisedMessage("^5Friendly Fire ^7[^5OFF^7]");
}
toggleTrickshotDistance()
{
    if (!isDefined(self.trickshotDistanceOn))
        self.trickshotDistanceOn = true;
    self.trickshotDistanceOn = !self.trickshotDistanceOn;
    if (self.trickshotDistanceOn)
        self thread rainyShowRaisedMessage("^7Trickshot Distance ^7[^5ON^7]");
    else
        self thread rainyShowRaisedMessage("^7Trickshot Distance ^7[^5OFF^7]");
}
toggleAlmostHits()
{
    if (!isDefined(self.almostHitsOn))
        self.almostHitsOn = true;
    self.almostHitsOn = !self.almostHitsOn;
    if (self.almostHitsOn)
        self thread rainyShowRaisedMessage("^5Almost Hits ^7[^5ON^7]");
    else
        self thread rainyShowRaisedMessage("^5Almost Hits ^7[^5OFF^7]");
}
toggleTsPlatformBind()
{
    // Toggles whether the "Crouch + Dpad Left" bind (spawnPlatformBindMonitor)
    // actually spawns a platform on press. Doesn't touch the menu item itself
    // ("Spawn Trickshot Platform" on the Spawnables page still always works) -
    // this only gates the quick-bind shortcut.
    if (!isDefined(self.rainyTsPlatformBindOn))
        self.rainyTsPlatformBindOn = true;
    self.rainyTsPlatformBindOn = !self.rainyTsPlatformBindOn;
    if (self.rainyTsPlatformBindOn)
        self thread rainyShowRaisedMessage("^5TS Platform Bind ^7[^5ON^7] - Crouch + Dpad Left");
    else
        self thread rainyShowRaisedMessage("^5TS Platform Bind ^7[^5OFF^7]");
}
toggleAutoRefillAmmo()
{
    if (!isDefined(self.rainyAutoRefillAmmo))
        self.rainyAutoRefillAmmo = false;
    self.rainyAutoRefillAmmo = !self.rainyAutoRefillAmmo;
    if (self.rainyAutoRefillAmmo)
    {
        self thread rainyShowRaisedMessage("^5Auto Refill Ammo ^7[^5ON^7]");
        // Top everything off immediately on enable instead of waiting for the next
        // reload/equipment use to trigger a refill.
        self rainyAutoRefillTick();
        self thread rainyAutoRefillAmmoLoop();
    }
    else
    {
        self thread rainyShowRaisedMessage("^5Auto Refill Ammo ^7[^5OFF^7]");
        self notify("stopAutoRefillAmmo");
    }
}
toggleInfiniteCarePackage()
{
    if (!isDefined(self.rainyInfiniteCarePackage))
        self.rainyInfiniteCarePackage = false;
    self.rainyInfiniteCarePackage = !self.rainyInfiniteCarePackage;

    if (self.rainyInfiniteCarePackage)
    {
        self thread rainyShowRaisedMessage("^7Infinite Care Package ^7[^5ON^7]");
        self notify("stopInfiniteCarePackage");
        self rainyGiveCarePackageOnce();
        self thread rainyInfiniteCarePackageLoop();
    }
    else
    {
        self thread rainyShowRaisedMessage("^7Infinite Care Package ^7[^5OFF^7]");
        self notify("stopInfiniteCarePackage");
    }
}
rainyGiveCarePackageOnce()
{
    if (!isDefined(self) || !isAlive(self))
        return;

    self maps\mp\killstreaks\_killstreaks::tryGiveKillstreak("airdrop", 4);
}
rainyInfiniteCarePackageLoop()
{
    self endon("disconnect");
    self endon("death");
    self endon("stopInfiniteCarePackage");
    level endon("game_ended");
    level endon("rainy_shutdown");

    for (;;)
    {
        self waittill("weapon_fired", firedWeapon);

        if (!isDefined(self.rainyInfiniteCarePackage) || !self.rainyInfiniteCarePackage)
            return;

        // Care Package uses the airdrop marker. Re-give only after that marker is
        // thrown instead of spamming tryGiveKillstreak every frame and risking stacks.
        if (isDefined(firedWeapon) && isSubStr(firedWeapon, "airdrop"))
        {
            wait 0.25;
            if (isDefined(self.rainyInfiniteCarePackage) && self.rainyInfiniteCarePackage && isAlive(self))
                self rainyGiveCarePackageOnce();
        }
    }
}
toggleForgeMode()
{
    if (!isDefined(self.rainyForgeMode))
        self.rainyForgeMode = false;
    if (!isDefined(self.forge_mode))
        self.forge_mode = false;

    self.rainyForgeMode = !self.rainyForgeMode;
    self.forge_mode = self.rainyForgeMode;

    if (self.rainyForgeMode)
    {
        self thread rainyShowRaisedMessage("^5Forge Mode ^7[^5ON^7] - Hold ADS to move objects");
        self notify("stopForgeMode");
        self thread rainyForgeModeLoop();
    }
    else
    {
        self thread rainyShowRaisedMessage("^5Forge Mode ^7[^5OFF^7]");
        self.forge_mode = false;
        self notify("stopForgeMode");
    }
}
/*
    No Player Collision: confirmed working via direct console testing.
    bg_playerCollision controls whether players collide with each other at
    all; bg_playerEjection controls the push-apart force applied when they
    overlap. Both must be zeroed together - bg_playerCollision alone left
    the push force active and players still blocked each other. Both are
    IW4x server-authoritative, cheat-protected dvars (bg_playerCollision was
    renamed from g_playerCollision, and vice versa for bg_playerEjection),
    genuine level-wide server dvars like g_gravity/camera_thirdPerson, so a
    single setDvar from the host affects the whole lobby (bots included,
    since bots are still players engine-side) with no per-player loop needed.
*/
toggleNoPlayerCollision()
{
    if (!isDefined(level.rainyNoPlayerCollision))
        level.rainyNoPlayerCollision = false;
    level.rainyNoPlayerCollision = !level.rainyNoPlayerCollision;
    if (level.rainyNoPlayerCollision)
    {
        setDvar("bg_playerCollision", "0");
        setDvar("bg_playerEjection", "0");
        self thread rainyShowRaisedMessage("^7No Player Collision ^7[^5ON^7]");
    }
    else
    {
        setDvar("bg_playerCollision", "1");
        setDvar("bg_playerEjection", "1");
        self thread rainyShowRaisedMessage("^7No Player Collision ^7[^5OFF^7]");
    }
}
rainyForgeModeLoop()
{
    self endon("disconnect");
    self endon("stopForgeMode");
    level endon("game_ended");
    level endon("rainy_shutdown");

    while (true)
    {
        if (!isDefined(self.rainyForgeMode) || !self.rainyForgeMode)
            return;

        self.forge_mode = self.rainyForgeMode;

        trace = bullettrace(self getTagOrigin("j_head"), self getTagOrigin("j_head") + anglesToForward(self getPlayerAngles()) * 1000000, 1, self);
        if (isDefined(trace["entity"]))
        {
            // Move the real entity. For a care package this is the actual stock
            // crate (use trigger + collision intact), so it stays capturable and
            // the keep-alive loop keeps it from despawning wherever you park it.
            ent = trace["entity"];
            if (self adsButtonPressed())
            {
                while (self adsButtonPressed() && isDefined(ent))
                {
                    ent moveTo(self getTagOrigin("j_head") + anglesToForward(self getPlayerAngles()) * 200, .5);
                    ent.origin = self getTagOrigin("j_head") + anglesToForward(self getPlayerAngles()) * 200;
                    wait .01;
                }
            }
            if (isDefined(ent) && self attackButtonPressed())
            {
                while (self attackButtonPressed() && isDefined(ent))
                {
                    ent rotatePitch(1, .01);
                    wait .01;
                }
            }
            if (isDefined(ent) && self fragButtonPressed())
            {
                while (self fragButtonPressed() && isDefined(ent))
                {
                    ent rotateYaw(1, .01);
                    wait .01;
                }
            }
            if (isDefined(ent) && self secondaryOffhandButtonPressed())
            {
                while (self secondaryOffhandButtonPressed() && isDefined(ent))
                {
                    ent rotateRoll(1, .01);
                    wait .01;
                }
            }
            if (isDefined(ent) && !isPlayer(ent) && self meleeButtonPressed())
            {
                ent delete();
                wait .2;
            }
        }
        wait .05;
    }
}
/*
    Care package persistence - how it actually works (verified against stock
    maps\mp\killstreaks\_airdrop.gsc):

    A landed crate is removed by stock dropTimeOut(), which 90s after the crate
    settles does:  while ( crate.curProgress != 0 ) wait 1;  crate delete();
    So the crate is deleted at the 90s mark ONLY while curProgress is 0. Hold
    curProgress at a nonzero value and that while-loop spins forever - the crate
    never despawns. That single field is the entire lever; nothing else in stock
    deletes an idle crate.

    Capture is NOT broken by this. When a player holds Use, stock useHoldThink()
    sets inUse=true, resets curProgress to 0 and drives it up to useTime itself,
    then on finish sets inUse=false and curProgress=0. So we only pin curProgress
    while inUse is false - the instant a real capture starts we let go, the stock
    capture bar runs untouched, and on a completed capture stock deleteCrate()
    consumes the crate exactly as normal. This keeps care package stalls working.

    Earlier builds only pinned forge-grabbed crates, so untouched ground crates
    still timed out; and the convert-to-script_model approach killed capture
    because the replacement had no makeUsable trigger. One level loop covering
    every "care_package" crate fixes both: persistent AND capturable AND, since
    it's still the real crate, freely movable by forge with its use trigger and
    collision intact.
*/
rainyCarePackageKeepAliveLoop()
{
    level endon("game_ended");
    level endon("rainy_shutdown");

    /*
        Care package persistence - verified against stock _airdrop.gsc.

        The ONLY thing that deletes an idle, landed crate is stock dropTimeOut():

            if ( dropCrate.dropType == "nuke_drop" )
                return;                          // <- early out, never deletes
            waitLongDuration( 90.0 );
            while ( dropCrate.curProgress != 0 )
                wait 1;
            dropCrate delete();

        The previous build pinned curProgress nonzero. That works for an untouched
        crate, but care-package STALLING repeatedly engages the capture hold, and
        stock useHoldThink() sets curProgress back to 0 the instant each hold ends.
        On a 90s+ crate, dropTimeOut is already spinning in that while-loop, so a
        hold-release that lands on its once-per-second sample deletes the crate.
        That's the sky-crate-during-a-stall despawn. curProgress is the capture
        field, so any keep-alive built on it inherently races the capture.

        Real fix: flip the crate's dropType FIELD to "nuke_drop". dropTimeOut then
        returns before the 90s wait and never reads curProgress at all - so capture
        can zero curProgress as much as it likes with nothing to race. This does NOT
        change capture or rewards: the crate's think function (killstreakCrateThink)
        was dispatched at spawn from a separate LOCAL dropType, and the capture
        reward keys off self.crateType, not the dropType field. The field is read
        nowhere else that affects an airdrop crate.

        Must be set before the crate lands (before dropTimeOut reads it). The crate
        carries targetname "care_package" from creation, all through the heli
        delivery, so this 10Hz scan disarms it many seconds before touchdown.
    */
    for (;;)
    {
        crates = getEntArray("care_package", "targetname");
        for (i = 0; i < crates.size; i++)
        {
            c = crates[i];
            if (!isDefined(c))
                continue;

            // PRIMARY (race-free): disarm dropTimeOut once per crate.
            if (!isDefined(c.rainyTimeoutDisarmed))
            {
                c.dropType = "nuke_drop";
                c.rainyTimeoutDisarmed = true;
            }

            // FALLBACK only (in case a client's dropTimeOut lacks the nuke_drop
            // early-out): hold curProgress nonzero while idle. Skipped during a
            // capture so the stock hold-bar stays clean. Moot when the primary
            // lever is active, since dropTimeOut returns before reading curProgress.
            if (isDefined(c.inUse) && c.inUse)
                continue;
            c.curProgress = 1;
        }
        wait 0.1;
    }
}
rainyAutoRefillTick()
{
    // One pass: top off stock on the current weapon, every carried primary, and every
    // lethal/tactical the player has equipped. Called immediately on toggle-on, and
    // every tick of rainyAutoRefillAmmoLoop while the mod is active.
    current = self getCurrentWeapon();
    if (isDefined(current) && current != "none" && !isSubStr(current, "knife"))
    {
        self setWeaponAmmoStock(current, 999);
        // Top off the clip too, but only if it's not already full — this keeps a
        // reload feeling instant (stock is never the bottleneck) while still letting
        // the clip itself drain normally during sustained fire between reloads.
    }
    carriedWeapons = self getWeaponsListPrimaries();
    for (i = 0; i < carriedWeapons.size; i++)
    {
        w = carriedWeapons[i];
        if (isDefined(w) && w != "none" && !isSubStr(w, "knife"))
            self setWeaponAmmoStock(w, 999);
    }
    // Lethal/tactical: only refresh stock for whatever the player actually has
    // equipped (checked via getWeaponAmmoStock returning a defined, non-zero-max
    // value means it's in their loadout), and only when it's below its known max so
    // we're not spamming setWeaponAmmoStock 20x/sec for empty-slot items.
    self rainyRefillEquippedLethalTactical();
}
rainyRefillEquippedLethalTactical()
{
    // Each entry: weapon name -> max stock count for that equipment type.
    self rainyRefillIfBelowMax("frag_grenade_mp", 1);
    self rainyRefillIfBelowMax("semtex_mp", 1);
    self rainyRefillIfBelowMax("throwingknife_mp", 1);
    self rainyRefillIfBelowMax("claymore_mp", 1);
    self rainyRefillIfBelowMax("c4_mp", 1);
    self rainyRefillIfBelowMax("bouncingbetty_mp", 1);
    self rainyRefillIfBelowMax("flash_grenade_mp", 2);
    self rainyRefillIfBelowMax("concussion_grenade_mp", 2);
    self rainyRefillIfBelowMax("smoke_grenade_mp", 1);
    self rainyRefillIfBelowMax("trophy_mp", 1);
    self rainyRefillIfBelowMax("portable_radar_mp", 1);
}
rainyRefillIfBelowMax(weaponName, maxStock)
{
    // hasWeapon guards against granting stock for equipment the player doesn't
    // actually have equipped on their loadout.
    if (!self hasWeapon(weaponName))
        return;
    stock = self getWeaponAmmoStock(weaponName);
    if (!isDefined(stock) || stock < maxStock)
        self setWeaponAmmoStock(weaponName, maxStock);
}
rainyAutoRefillAmmoLoop()
{
    // Polls ammo state directly instead of waiting on "weapon_change", which only
    // fires on a weapon SWITCH, not on a same-weapon reload completing. That gap was
    // why reloading the active gun felt slow/inconsistent — the loop simply wasn't
    // waking up until the player swapped weapons. Polling every 0.05s catches a
    // reload or equipment throw essentially the instant it happens, on the same
    // weapon, with no switch required.
    self endon("disconnect");
    self endon("death");
    self endon("stopAutoRefillAmmo");
    level endon("game_ended");
    level endon("rainy_shutdown");
    for (;;)
    {
        wait 0.05;
        if (!isDefined(self.rainyAutoRefillAmmo) || !self.rainyAutoRefillAmmo)
            return;
        self rainyAutoRefillTick();
    }
}
toggleCanswapBind()
{
    if (!isDefined(self.canswapBound) || !self.canswapBound)
    {
        self.canswapBound = true;
        self thread canswapBindMonitor();
        self thread rainyShowRaisedMessage("^5Canswap Bind ^7[^5ON^7] - Standing + Dpad Up");
    }
    else
    {
        self.canswapBound = false;
        self notify("stop_canswap_bind");
        self thread rainyShowRaisedMessage("^5Canswap Bind ^7[^5OFF^7]");
    }
}
canswapBindMonitor()
{
    self endon("disconnect");
    self endon("stop_canswap_bind");
    level endon("game_ended");
    level endon("rainy_shutdown");
    // D-pad up (+actionslot 1), gated to standing only. The host also uses
    // D-pad up for menu scroll-up while the menu is open, but the menuOpen
    // check right below already skips canswap whenever the menu is open, so
    // there's no real collision - D-pad up only ever does one or the other
    // depending on whether the menu is currently open. Change "+actionslot 1"
    // here to rebind to a different button.
    self notifyOnPlayerCommand("rainy_canswap_btn", "+actionslot 1");
    for (;;)
    {
        self waittill("rainy_canswap_btn");
        if (isDefined(self.menuOpen) && self.menuOpen)
            continue;
        if (self GetStance() != "stand")
            continue;
        self thread doCanswap();
        wait 0.1;
    }
}
/*
    Host-only quick-toggle binds for UFO Mode, TS Aimbot, and Spawn Trickshot
    Platform. Each just calls the exact same function the menu item already
    calls (toggleUFO/toggleTsAimbot/spawnPlatformGrid) - the bind is purely an
    alternate trigger, not a separate code path, so there's nothing new to
    keep in sync if those functions ever change.

    Bind/stance map for all three (host-only, so no collision with anything
    non-host players use):
      - UFO Mode:               D-pad down (+actionslot 2), aim + standing only
      - TS Aimbot:               D-pad up   (+actionslot 1), crouch only
      - Spawn Trickshot Platform: D-pad left (+actionslot 3), crouch only

    D-pad down (+actionslot 2) is shared with Save/Load (which only fires on
    prone/crouch) and the host's menu scroll-down (which only fires while the
    menu is open) - UFO's "standing" requirement never overlaps either of
    those, so all three behaviors coexist safely on the same physical button.
    The added "aim" requirement only narrows UFO further within its own
    standing-only window; it doesn't change this non-overlap with the other two.

    D-pad up (+actionslot 1) is shared with Canswap Bind (standing only) and
    the host's menu scroll-up (menu-open only) - "crouch" never overlaps
    either of those for the same reason.
*/
ufoBindMonitor()
{
    self endon("disconnect");
    level endon("game_ended");
    level endon("rainy_shutdown");
    if (!isDefined(self.rainyWasHost) || !self.rainyWasHost)
        return;
    self notifyOnPlayerCommand("rainy_ufo_btn", "+actionslot 2");
    for (;;)
    {
        self waittill("rainy_ufo_btn");
        if (isDefined(self.menuOpen) && self.menuOpen)
            continue;
        if (isDefined(self.rainyBlockUfoBind) && self.rainyBlockUfoBind)
            continue;
        if (!self adsButtonPressed())
            continue;
        if (self GetStance() != "stand")
            continue;
        self toggleUFO();
        wait 0.3;
    }
}
tsAimbotBindMonitor()
{
    self endon("disconnect");
    level endon("game_ended");
    level endon("rainy_shutdown");
    if (!isDefined(self.rainyWasHost) || !self.rainyWasHost)
        return;
    self notifyOnPlayerCommand("rainy_tsaimbot_btn", "+actionslot 1");
    for (;;)
    {
        self waittill("rainy_tsaimbot_btn");
        if (isDefined(self.menuOpen) && self.menuOpen)
            continue;
        if (self GetStance() != "crouch")
            continue;
        self toggleTsAimbot();
        wait 0.3;
    }
}
spawnPlatformBindMonitor()
{
    self endon("disconnect");
    level endon("game_ended");
    level endon("rainy_shutdown");
    if (!isDefined(self.rainyWasHost) || !self.rainyWasHost)
        return;
    self notifyOnPlayerCommand("rainy_spawnplatform_btn", "+actionslot 3");
    for (;;)
    {
        self waittill("rainy_spawnplatform_btn");
        if (isDefined(self.menuOpen) && self.menuOpen)
            continue;
        if (!isDefined(self.rainyTsPlatformBindOn) || !self.rainyTsPlatformBindOn)
            continue;
        if (self GetStance() != "crouch")
            continue;
        self thread spawnPlatformGrid();
        wait 0.3;
    }
}
doCanswap()
{
    self endon("disconnect");
    gun = self getCurrentWeapon();
    if (!isDefined(gun) || gun == "none")
    {
        self thread rainyShowRaisedMessage("^5Canswap: no weapon held");
        return;
    }
    // Find the other weapon to cycle to (the swap that preserves the animation).
    weapons = self getWeaponsListPrimaries();
    if (!isDefined(weapons) || weapons.size == 0)
        weapons = self getWeaponsListAll();
    other = undefined;
    for (i = 0; i < weapons.size; i++)
    {
        if (weapons[i] != gun && weapons[i] != "none")
        {
            other = weapons[i];
            break;
        }
    }
    if (!isDefined(other))
    {
        self thread rainyShowRaisedMessage("^5Canswap: need a 2nd weapon (Overkill / give a secondary)");
        return;
    }
    // Restore the camo that was applied specifically to THIS gun, not just
    // whatever rainyCamoIndex currently holds (which reflects whichever gun was
    // most recently camo'd or given, not necessarily the canswap gun).
    //
    // BUG FIX: rainyCamoByWeapon is only ever populated when the player uses THIS
    // mod's own Give Camo menu. A camo that came from the player's actual in-game
    // class/loadout was never routed through this mod at all, so canswap had no
    // record of it and silently fell through to camo 0 (no camo) every time -
    // stripping a class-equipped camo on every canswap. The stock game itself
    // already resolves and stores each loadout weapon's camo index on the player
    // as self.loadoutPrimaryCamo/self.loadoutSecondaryCamo (set by the base
    // giveLoadout() when the class is given), alongside self.primaryWeapon/
    // self.secondaryWeapon identifying which weapon each belongs to. Checking
    // those next, before falling back to the old generic guess, means a
    // class-loadout camo now survives a canswap the same way a menu-given one
    // already did.
    camoIdx = 0;
    if (isDefined(self.rainyCamoByWeapon) && isDefined(self.rainyCamoByWeapon[gun]))
        camoIdx = self.rainyCamoByWeapon[gun];
    else if (isDefined(self.primaryWeapon) && gun == self.primaryWeapon && isDefined(self.loadoutPrimaryCamo))
        camoIdx = self.loadoutPrimaryCamo;
    else if (isDefined(self.secondaryWeapon) && gun == self.secondaryWeapon && isDefined(self.loadoutSecondaryCamo))
        camoIdx = self.loadoutSecondaryCamo;
    else if (isDefined(self.rainyCamoIndex))
        camoIdx = self.rainyCamoIndex;
    // The canswap only sticks when the gun's first-draw animation is interrupted by a
    // knife. GSC can't force a melee, so YOU knife as normal, then tap the bind. This
    // re-gives the gun (re-arming the first-draw animation) and cycles to the other gun
    // during your knife - automating the "pickup + Y" half of the manual trick.
    self takeWeapon(gun);
    self _giveWeapon(gun, camoIdx);
    self setWeaponAmmoClip(gun, 999);
    self setWeaponAmmoStock(gun, 999);
    self switchToWeapon(other);
}
spawnPlatformAtCrosshair()
{
    // Trace from the player's eye along their aim direction to find a world surface.
    // Spawn a solid care-package crate at that point so it acts as a stand-on platform.
    eyePos  = self getTagOrigin("j_head");
    forward = anglesToForward(self getPlayerAngles());
    endPos  = eyePos + (forward[0] * 5000, forward[1] * 5000, forward[2] * 5000);
    trace   = bulletTrace(eyePos, endPos, false, self);
    spawnPos = trace["position"];
    // Lift the crate half its height above the hit surface so it sits ON the surface
    // rather than clipping into it.
    spawnPos = (spawnPos[0], spawnPos[1], spawnPos[2] + 22);
    crate = spawn("script_model", spawnPos);
    if (!isDefined(crate))
    {
        self thread rainyShowRaisedMessage("^7Platform spawn failed");
        return;
    }
    crate setModel("com_plasticcase_friendly");
    // Unlink from UFO entity before registering the collision hull. Same reason as
    // spawnSingleCrate — CloneBrushModel resolving against a linked script_origin
    // near the player pins the entity and drops UFO state. Relink immediately after.
    inUfo = isDefined(self.ufoEnabled) && self.ufoEnabled;
    if (inUfo)
        self unlink();
    crate Solid();
    if (isDefined(level.airDropCrateCollision))
    {
        crate CloneBrushModelToScriptModel(level.airDropCrateCollision);
        if (inUfo && isDefined(self.ufoEntity))
            self playerLinkTo(self.ufoEntity);
        self thread rainyShowRaisedMessage("^7Platform Spawned");
    }
    else
    {
        if (inUfo && isDefined(self.ufoEntity))
            self playerLinkTo(self.ufoEntity);
        self thread rainyShowRaisedMessage("^7Platform Spawned (visual only on this map)");
    }
    // Track the handle so a future Delete Platforms option can clean them up.
    if (!isDefined(level.rainySpawnedCrates))
        level.rainySpawnedCrates = [];
    level.rainySpawnedCrates[level.rainySpawnedCrates.size] = crate;
}
spawnTrickshotPlatformAtCrosshair()
{
    // 4x4 trickshot platform placed at the crosshair surface hit point.
    eyePos  = self getTagOrigin("j_head");
    forward = anglesToForward(self getPlayerAngles());
    endPos  = eyePos + (forward[0] * 5000, forward[1] * 5000, forward[2] * 5000);
    trace   = bulletTrace(eyePos, endPos, false, self);
    hit = trace["position"];
    // Lift crate centres so their top surfaces sit flush at the hit point.
    centreZ = hit[2] + 22;
    startOff = -51;
    step = 34;
    for (gx = 0; gx < 4; gx++)
    {
        for (gy = 0; gy < 4; gy++)
        {
            ox = startOff + gx * step;
            oy = startOff + gy * step;
            spawnPos = (hit[0] + ox, hit[1] + oy, centreZ);
            self spawnSingleCrate(spawnPos);
        }
    }
    self thread rainyShowRaisedMessage("^7Trickshot Platform Spawned");
}
spawnPlatformBelow()
{
    pos = self.origin;
    spawnPos = (pos[0], pos[1], pos[2] - 16);
    self spawnSingleCrate(spawnPos);
    self thread rainyShowRaisedMessage("^5Platform Spawned Below");
}
spawnPlatformGrid()
{
    // Sequential spawns, no threading. Step of 43 closes the gap between crates.
    // startOff = -(3*43/2) = -64 centres the 4x4 grid on the player.
    pos = self.origin;
    startOff = -51;
    step = 34;
    for (gx = 0; gx < 4; gx++)
    {
        for (gy = 0; gy < 4; gy++)
        {
            ox = startOff + gx * step;
            oy = startOff + gy * step;
            spawnPos = (pos[0] + ox, pos[1] + oy, pos[2] - 16);
            self spawnSingleCrate(spawnPos);
        }
    }
    self thread rainyShowRaisedMessage("^5Platform Grid Spawned (4x4)");
}
spawnSingleCrate(spawnPos)
{
    crate = spawn("script_model", spawnPos);
    if (!isDefined(crate))
        return;
    crate setModel("com_plasticcase_friendly");
    // Unlink from UFO entity before registering the collision hull. CloneBrushModel
    // resolving against a linked script_origin near the player pins the entity and
    // drops the player out of UFO state. Relink immediately after.
    inUfo = isDefined(self.ufoEnabled) && self.ufoEnabled;
    if (inUfo)
        self unlink();
    crate Solid();
    if (isDefined(level.airDropCrateCollision))
        crate CloneBrushModelToScriptModel(level.airDropCrateCollision);
    if (inUfo && isDefined(self.ufoEntity))
        self playerLinkTo(self.ufoEntity);
    if (!isDefined(level.rainySpawnedCrates))
        level.rainySpawnedCrates = [];
    level.rainySpawnedCrates[level.rainySpawnedCrates.size] = crate;
}

removeAllPlatforms()
{
    if (!isDefined(level.rainySpawnedCrates) || level.rainySpawnedCrates.size == 0)
    {
        self thread rainyShowRaisedMessage("^5No Platforms To Remove");
        return;
    }
    count = 0;
    for (i = 0; i < level.rainySpawnedCrates.size; i++)
    {
        // Store in a local var first - GSC can't call methods on array subscript expressions
        c = level.rainySpawnedCrates[i];
        if (isDefined(c))
        {
            c delete();
            count++;
        }
    }
    level.rainySpawnedCrates = [];
    self thread rainyShowRaisedMessage("^5Removed " + count + " Platform(s)");
}
rainyVectorDot(vecA, vecB)
{
    return (vecA[0] * vecB[0]) + (vecA[1] * vecB[1]) + (vecA[2] * vecB[2]);
}

getAimbotTarget(ignoreWalls)
{
    bestTarget = undefined;
    bestAimError = 9999999;
    bestDist = 9999999;

    players = level.players;
    if (!isDefined(players))
        return undefined;

    myOrigin = self getTagOrigin("j_head");
    myForward = anglesToForward(self GetPlayerAngles());

    for (i = 0; i < players.size; i++)
    {
        target = players[i];

        if (!isDefined(target))
            continue;
        if (target == self)
            continue;
        if (!isDefined(target.sessionstate) || target.sessionstate != "playing")
            continue;
        if (!isAlive(target))
            continue;
        if (!target isBot())
            continue;

        if (isDefined(level.teamBased) && level.teamBased)
        {
            if (isDefined(self.pers["team"]) && isDefined(target.pers["team"]))
            {
                if (self.pers["team"] == target.pers["team"])
                    continue;
            }
        }

        targetOrigin = target getEye();

        if (!ignoreWalls)
        {
            trace = bulletTrace(myOrigin, targetOrigin, false, self);
            if (trace["fraction"] < 1.0)
                continue;
        }

        toTarget = targetOrigin - myOrigin;
        dist = distance(myOrigin, targetOrigin);

        if (dist <= 0)
            continue;

        // Project the bot onto the player's aim ray. Anything behind the player
        // should not be eligible for crosshair-priority targeting.
        forwardDist = rainyVectorDot(toTarget, myForward);
        if (forwardDist <= 0)
            continue;

        // Crosshair closeness = angular error from the aim ray, not world distance.
        // This keeps a far bot directly under the crosshair from losing to a closer
        // bot that is visibly farther off-center.
        crossDistSq = (dist * dist) - (forwardDist * forwardDist);
        if (crossDistSq < 0)
            crossDistSq = 0;

        aimError = crossDistSq / (dist * dist);

        if (aimError < bestAimError || (aimError == bestAimError && dist < bestDist))
        {
            bestAimError = aimError;
            bestDist = dist;
            bestTarget = target;
        }
    }

    return bestTarget;
}
rainySetWallbangDvars(enabled)
{
    if (enabled)
    {
        setDvar("bg_surfacePenetration", "9999");
        setDvar("bg_bulletExplDmgFactor", "9999");
        setDvar("bg_bulletRange", "99999");
        setDvar("bg_penetrationMinDmgMult", "1.0");
        setDvar("bg_fallbackExplosionDamage", "9999");
        setDvar("bg_bulletDmgMultPenetrationSmall", "9999");
        setDvar("bg_bulletDmgMultPenetrationMedium", "9999");
        setDvar("perk_bulletPenetrationMultiplier", "30");
        setDvar("perk_armorPiercing", "9999");
        setDvar("bullet_ricochetBaseChance", "0.95");
        setDvar("bullet_penetrationMinFxDist", "1024");
        setDvar("bulletrange", "50000");
    }
    else
    {
        setDvar("bg_surfacePenetration", "11");
        setDvar("bg_bulletExplDmgFactor", "1");
        setDvar("bg_bulletRange", "8192");
        setDvar("bg_penetrationMinDmgMult", "0.1");
        setDvar("bg_fallbackExplosionDamage", "0");
        setDvar("bg_bulletDmgMultPenetrationSmall", "0.075");
        setDvar("bg_bulletDmgMultPenetrationMedium", "0.075");
        setDvar("perk_bulletPenetrationMultiplier", "1");
        setDvar("perk_armorPiercing", "1");
        setDvar("bullet_ricochetBaseChance", "0");
        setDvar("bullet_penetrationMinFxDist", "0");
        setDvar("bulletrange", "8192");
    }
}
rainyRefreshWallbangDvars()
{
    enabled = false;
    if (isDefined(self.wallbangOn) && self.wallbangOn)
        enabled = true;
    if (isDefined(self.wallbangSnapOn) && self.wallbangSnapOn)
        enabled = true;
    self rainySetWallbangDvars(enabled);
}
rainyWallbangDvarKeepAliveLoop()
{
    self endon("disconnect");
    level endon("game_ended");
    level endon("rainy_shutdown");

    for (;;)
    {
        // Only re-apply the hot wallbang profile while one of the two wallbang
        // modes owns it. When both are OFF, leave the normal/off profile alone so
        // the toggle OFF state does not get fought by this watchdog.
        if ((isDefined(self.wallbangOn) && self.wallbangOn) || (isDefined(self.wallbangSnapOn) && self.wallbangSnapOn))
            self rainySetWallbangDvars(true);

        wait 1;
    }
}
rainyDisableAimbotModesExcept(keepMode)
{
    if (keepMode != "ts" && isDefined(self.tsAimbotOn) && self.tsAimbotOn)
    {
        self.tsAimbotOn = false;
        self notify("stopTsAimbot");
    }
    if (keepMode != "unfair" && isDefined(self.unfairAimbotOn) && self.unfairAimbotOn)
    {
        self.unfairAimbotOn = false;
        self notify("stopUnfairAimbot");
    }
    if (keepMode != "silent" && isDefined(self.silentAimOn) && self.silentAimOn)
    {
        self.silentAimOn = false;
        self notify("stopSilentAim");
    }
    if (keepMode != "snap" && isDefined(self.snapAimOn) && self.snapAimOn)
    {
        self.snapAimOn = false;
        self notify("stopSnapAim");
    }
    if (keepMode != "wbsnap" && isDefined(self.wallbangSnapOn) && self.wallbangSnapOn)
    {
        self.wallbangSnapOn = false;
        self notify("stopWallbangSnap");
        self rainyRefreshWallbangDvars();
    }
}
toggleWallbang()
{
    if (!isDefined(self.wallbangOn))
        self.wallbangOn = false;
    self.wallbangOn = !self.wallbangOn;
    if (self.wallbangOn)
    {
        // Wallbang Everything and Wallbang + Snap Aim both own the same penetration dvars.
        // Keep them mutually exclusive so one mode cannot reset the other's dvars.
        if (isDefined(self.wallbangSnapOn) && self.wallbangSnapOn)
        {
            self.wallbangSnapOn = false;
            self notify("stopWallbangSnap");
        }
        self rainyRefreshWallbangDvars();
        self thread rainyShowRaisedMessage("^7Wallbang Everything ^7[^5ON^7]");
    }
    else
    {
        self rainyRefreshWallbangDvars();
        self thread rainyShowRaisedMessage("^7Wallbang Everything ^7[^5OFF^7]");
    }
}
toggleWallbangSnap()
{
    if (!isDefined(self.wallbangSnapOn))
        self.wallbangSnapOn = false;
    self.wallbangSnapOn = !self.wallbangSnapOn;
    if (self.wallbangSnapOn)
    {
        // Wallbang + Snap Aim is both a wallbang mode and an aimbot mode.
        // Gate it against Wallbang Everything and the other Aimbot Options loops.
        if (isDefined(self.wallbangOn) && self.wallbangOn)
            self.wallbangOn = false;
        self rainyDisableAimbotModesExcept("wbsnap");
        self rainyRefreshWallbangDvars();
        self notify("stopWallbangSnap");
        self thread wallbangSnapLoop();
        self thread rainyShowRaisedMessage("^5Wallbang + Snap Aim ^7[^5ON^7]");
    }
    else
    {
        self notify("stopWallbangSnap");
        self rainyRefreshWallbangDvars();
        self thread rainyShowRaisedMessage("^5Wallbang + Snap Aim ^7[^5OFF^7]");
    }
}
wallbangSnapLoop()
{
    self endon("disconnect");
    self endon("death");
    self endon("stopWallbangSnap");
    level endon("game_ended");
    level endon("rainy_shutdown");

    // Wallbang + Snap Aim uses the exact same penetration/damage dvar profile as
    // Wallbang Everything. Refresh it as the loop starts so this mode never feels
    // weaker because another script reset the global dvars.
    self rainyRefreshWallbangDvars();

    for (;;)
    {
        if (self adsButtonPressed())
        {
            target = self getAimbotTarget(true);
            if (isDefined(target) && isAlive(target))
            {
                myHead = self getTagOrigin("j_head");
                targetHead = target getEye();
                toTarget = targetHead - myHead;
                self SetPlayerAngles(VectorToAngles(toTarget));
            }
        }
        wait 0.05;
    }
}
toggleTsAimbot()
{
    if (!isDefined(self.tsAimbotOn))
        self.tsAimbotOn = false;
    self.tsAimbotOn = !self.tsAimbotOn;
    if (self.tsAimbotOn)
    {
        self rainyDisableAimbotModesExcept("ts");
        self notify("stopTsAimbot");
        self thread tsAimbotLoop();
        self thread rainyShowRaisedMessage("^5TS Aimbot ^7[^5ON^7]");
    }
    else
    {
        self notify("stopTsAimbot");
        self thread rainyShowRaisedMessage("^5TS Aimbot ^7[^5OFF^7]");
    }
}
tsAimbotLoop()
{
    self endon("disconnect");
    self endon("death");
    self endon("stopTsAimbot");
    level endon("game_ended");
    level endon("rainy_shutdown");

    for (;;)
    {
        // Wait for the engine to confirm an actual shot fired. Checking
        // attackButtonPressed() directly let TS Aimbot kill from any trigger pull,
        // even during animations/reloads/stalls where no bullet actually left the gun.
        self waittill("weapon_fired");

        weapon = self getCurrentWeapon();

        // TS Aimbot should only assist real no-scope sniper shots.
        if (!rainyIsSniperRifle(weapon))
            continue;

        // Strict no-scope only: if ADS is held at the moment the shot fires, do nothing.
        if (self adsButtonPressed())
            continue;

        target = self getAimbotTarget(true);
        if (isDefined(target) && isAlive(target))
        {
            target thread [[level.callbackPlayerDamage]](
                self,
                self,
                100,
                0,
                "MOD_HEAD_SHOT",
                weapon,
                (0,0,0),
                (0,0,0),
                "head",
                0
            );
        }
    }
}

toggleUnfairAimbot()
{
    if (!isDefined(self.unfairAimbotOn))
        self.unfairAimbotOn = false;
    self.unfairAimbotOn = !self.unfairAimbotOn;
    if (self.unfairAimbotOn)
    {
        self rainyDisableAimbotModesExcept("unfair");
        self notify("stopUnfairAimbot");
        self thread unfairAimbotLoop();
        self thread rainyShowRaisedMessage("^7Unfair Aimbot ^7[^5ON^7]");
    }
    else
    {
        self notify("stopUnfairAimbot");
        self thread rainyShowRaisedMessage("^7Unfair Aimbot ^7[^5OFF^7]");
    }
}
unfairAimbotLoop()
{
    self endon("disconnect");
    self endon("death");
    self endon("stopUnfairAimbot");
    level endon("game_ended");
    level endon("rainy_shutdown");

    for (;;)
    {
        // This is the old v3l TS Aimbot behavior split into its own mode:
        // real no-scope sniper shot only, then direct headshot damage to the
        // closest valid enemy bot, ignoring walls.
        self waittill("weapon_fired");

        weapon = self getCurrentWeapon();

        if (!rainyIsSniperRifle(weapon))
            continue;

        if (self adsButtonPressed())
            continue;

        target = self getUnfairAimbotTarget(true);
        if (isDefined(target) && isAlive(target))
        {
            target thread [[level.callbackPlayerDamage]](
                self,
                self,
                100,
                0,
                "MOD_HEAD_SHOT",
                weapon,
                (0,0,0),
                (0,0,0),
                "head",
                0
            );
        }
    }
}
getUnfairAimbotTarget(ignoreWalls)
{
    bestTarget = undefined;
    bestDist = 9999999;
    players = level.players;

    if (!isDefined(players))
        return undefined;

    myOrigin = self getTagOrigin("j_head");

    for (i = 0; i < players.size; i++)
    {
        target = players[i];

        if (!isDefined(target))
            continue;
        if (target == self)
            continue;
        if (!isDefined(target.sessionstate) || target.sessionstate != "playing")
            continue;
        if (!isAlive(target))
            continue;
        if (!target isBot())
            continue;

        if (isDefined(level.teamBased) && level.teamBased)
        {
            if (isDefined(self.pers["team"]) && isDefined(target.pers["team"]))
            {
                if (self.pers["team"] == target.pers["team"])
                    continue;
            }
        }

        targetOrigin = target getEye();

        if (!ignoreWalls)
        {
            trace = bulletTrace(myOrigin, targetOrigin, false, self);
            if (trace["fraction"] < 1.0)
                continue;
        }

        dist = distance(myOrigin, targetOrigin);
        if (dist < bestDist)
        {
            bestDist = dist;
            bestTarget = target;
        }
    }

    return bestTarget;
}

toggleSilentAim()
{
    if (!isDefined(self.silentAimOn))
        self.silentAimOn = false;
    self.silentAimOn = !self.silentAimOn;
    if (self.silentAimOn)
    {
        self rainyDisableAimbotModesExcept("silent");
        self notify("stopSilentAim");
        self thread silentAimLoop();
        self thread rainyShowRaisedMessage("^7Silent Aim ^7[^5ON^7]");
    }
    else
    {
        self notify("stopSilentAim");
        self thread rainyShowRaisedMessage("^7Silent Aim ^7[^5OFF^7]");
    }
}
silentAimLoop()
{
    self endon("disconnect");
    self endon("death");
    self endon("stopSilentAim");
    level endon("game_ended");
    level endon("rainy_shutdown");
    wasAttacking = false;
    for (;;)
    {
        attackNow = self attackButtonPressed();
        if (attackNow && !wasAttacking)
        {
            target = self getAimbotTarget(false);
            if (isDefined(target) && isAlive(target))
            {
                savedAngles = self GetPlayerAngles();
                myHead = self getTagOrigin("j_head");
                targetHead = target getEye();
                toTarget = targetHead - myHead;
                self SetPlayerAngles(VectorToAngles(toTarget));
                wait 0.05;
                self SetPlayerAngles(savedAngles);
            }
        }
        wasAttacking = attackNow;
        wait 0.05;
    }
}
toggleSnapAim()
{
    if (!isDefined(self.snapAimOn))
        self.snapAimOn = false;
    self.snapAimOn = !self.snapAimOn;
    if (self.snapAimOn)
    {
        self rainyDisableAimbotModesExcept("snap");
        self notify("stopSnapAim");
        self thread snapAimLoop();
        self thread rainyShowRaisedMessage("^5Snap Aim ^7[^5ON^7]");
    }
    else
    {
        self notify("stopSnapAim");
        self thread rainyShowRaisedMessage("^5Snap Aim ^7[^5OFF^7]");
    }
}
snapAimLoop()
{
    self endon("disconnect");
    self endon("death");
    self endon("stopSnapAim");
    level endon("game_ended");
    level endon("rainy_shutdown");
    for (;;)
    {
        if (self adsButtonPressed())
        {
            target = self getAimbotTarget(false);
            if (isDefined(target) && isAlive(target))
            {
                myHead = self getTagOrigin("j_head");
                targetHead = target getEye();
                toTarget = targetHead - myHead;
                self SetPlayerAngles(VectorToAngles(toTarget));
            }
        }
        wait 0.05;
    }
}
cycleJump()
{
    if (!isDefined(self.gravityLevel))
        self.gravityLevel = 1;
    self.gravityLevel++;
    if (self.gravityLevel > 10)
        self.gravityLevel = 1;
    setDvar("g_gravity", "800");
    if (self.gravityLevel == 1)
    {
        self notify("stopJumpBoost");
        self thread rainyShowRaisedMessage("^7Super Jump ^7[^51x ^7(Normal)^7]");
    }
    else
    {
        self notify("stopJumpBoost");
        self thread jumpBoostLoop();
        if (self.gravityLevel == 2)  self thread rainyShowRaisedMessage("^7Super Jump ^7[^52x^7]");
        else if (self.gravityLevel == 3)  self thread rainyShowRaisedMessage("^7Super Jump ^7[^53x^7]");
        else if (self.gravityLevel == 4)  self thread rainyShowRaisedMessage("^7Super Jump ^7[^54x^7]");
        else if (self.gravityLevel == 5)  self thread rainyShowRaisedMessage("^7Super Jump ^7[^55x^7]");
        else if (self.gravityLevel == 6)  self thread rainyShowRaisedMessage("^7Super Jump ^7[^56x^7]");
        else if (self.gravityLevel == 7)  self thread rainyShowRaisedMessage("^7Super Jump ^7[^57x^7]");
        else if (self.gravityLevel == 8)  self thread rainyShowRaisedMessage("^7Super Jump ^7[^58x^7]");
        else if (self.gravityLevel == 9)  self thread rainyShowRaisedMessage("^7Super Jump ^7[^59x^7]");
        else if (self.gravityLevel == 10) self thread rainyShowRaisedMessage("^7Super Jump ^7[^510x ^7(Massive)^7]");
    }
    // Fun Mods - Super Jump now applies lobby-wide: every other connected real
    // player (bots excluded) gets their own .gravityLevel set to match the host's
    // choice and gets jumpBoostLoop threaded on them, the same way it already
    // worked for self. jumpBoostLoop reads .gravityLevel off whoever it's running
    // on, so this is a straight per-target reuse of the existing self-only logic.
    if (!isDefined(level.players))
        return;
    for (i = 0; i < level.players.size; i++)
    {
        p = level.players[i];
        if (!isDefined(p)) continue;
        if (p == self) continue;
        if (rainyIsBot(p)) continue;
        p.gravityLevel = self.gravityLevel;
        p notify("stopJumpBoost");
        if (self.gravityLevel > 1)
            p thread jumpBoostLoop();
    }
}
jumpBoostLoop()
{
    self endon("disconnect");
    self endon("death");
    self endon("stopJumpBoost");
    level endon("game_ended");
    level endon("rainy_shutdown");
    wasOnGround = self isOnGround();
    for (;;)
    {
        onGround = self isOnGround();
        if (wasOnGround && !onGround)
        {
            jumpLvl = self.gravityLevel;
            boostZ = 0;
            if (jumpLvl == 2)       boostZ = 450;
            else if (jumpLvl == 3)  boostZ = 650;
            else if (jumpLvl == 4)  boostZ = 950;
            else if (jumpLvl == 5)  boostZ = 1300;
            else if (jumpLvl == 6)  boostZ = 1800;
            else if (jumpLvl == 7)  boostZ = 2600;
            else if (jumpLvl == 8)  boostZ = 3800;
            else if (jumpLvl == 9)  boostZ = 5500;
            else if (jumpLvl == 10) boostZ = 8000;
            if (boostZ > 0)
            {
                vel = self GetVelocity();
                self SetVelocity((vel[0], vel[1], boostZ));
            }
        }
        wasOnGround = onGround;
        wait 0.05;
    }
}
ufoLoop()
{
    // Movement only. Weapon suppression and respawn survival are separate threads.
    self endon("disconnect");
    self endon("StopUFO");
    // Added to match sibling ufoRespawnWatcher's scope (it already had both of
    // these). Safe even though this skips the unlink/delete at the bottom of this
    // function on a forced kill: rainyTeardownMenu() independently unlinks and
    // deletes self.ufoEntity during game_ended/rainy_shutdown teardown regardless,
    // so that cleanup still happens via that path instead of this one.
    level endon("game_ended");
    level endon("rainy_shutdown");
    if (isDefined(self.ufoEntity))
    {
        self.ufoEntity delete();
        self.ufoEntity = undefined;
    }
    self.ufoEntity = spawn("script_origin", self.origin, 1);
    self.ufoEntity.angles = self.angles;

    // ADS+UFO-bind gun glitch, take 2 (REVERTED): this used to delay the
    // playerLinkTo() below based on rainyAdsDownSince, theorizing playerLinkTo
    // itself was interrupting an in-progress ADS-raise animation. Decisive test
    // evidence disproved this: the very first ON ever (which runs this exact
    // same playerLinkTo call) was confirmed clean, while every ON after at
    // least one OFF glitched - if playerLinkTo mid-raise were the cause, the
    // first ON would glitch identically to every later one, since it's the
    // identical code path. It doesn't, so it isn't. Real fix is now in
    // rainyTearDownUfo (the OFF side) instead - see that function's comment.
    self playerLinkTo(self.ufoEntity);
    while (isDefined(self.ufoEnabled) && self.ufoEnabled)
    {
        forward = anglesToForward(self GetPlayerAngles());
        // UFO step scales with the Fun Mods speed setting (live), so changing speed
        // changes how fast UFO mode flies too: 1x/2x/3x/4x/5x/10x.
        step = 45 * self getRainySpeedMult();
        if (self FragButtonPressed())
            self.ufoEntity moveTo(self.ufoEntity.origin + (forward * step), 0.01);
        if (self SecondaryOffhandButtonPressed())
            self.ufoEntity moveTo(self.ufoEntity.origin - (forward * step), 0.01);
        wait 0.01;
    }
    self.ufoEnabled = false;
    self unlink();
    if (isDefined(self.ufoEntity))
    {
        self.ufoEntity delete();
        self.ufoEntity = undefined;
    }
}
ufoWeaponSuppressLoop()
{
    // Continuously re-applies disableweapons every tick while UFO is on.
    // The engine's spawn/respawn sequence re-enables weapons internally with no
    // scriptable hook to prevent it. Polling beats it reliably regardless of timing.
    self endon("disconnect");
    self endon("StopUFO");
    level endon("game_ended");
    level endon("rainy_shutdown");

    // A delay was added here in an earlier pass to fix the ADS+UFO-bind gun glitch,
    // theorizing disableweapons() was cutting off an in-progress ADS-raise animation.
    // That did NOT fix it in testing - confirmed via in-game testing that the glitch
    // still happens even when ADS is released immediately after the bind (so there's
    // nothing left for a delayed disableweapons() to interrupt), and that it never
    // happens on the UFO OFF transition, which never calls disableweapons() at all.
    // Real cause traced to playerLinkTo() in ufoLoop() instead - see the delay there
    // for the actual fix. Removed the dead delay from here; disableweapons() goes
    // back to firing on this loop's very first tick, every time, as it did originally.
    while (isDefined(self.ufoEnabled) && self.ufoEnabled)
    {
        self disableweapons();
        wait 0.05;
    }
}
ufoRespawnWatcher()
{
    // Re-establishes playerLinkTo after engine-forced respawns (prematch-end etc).
    // The engine breaks the link during its spawn sequence; we relink once it settles.
    // ufoWeaponSuppressLoop handles weapons independently so this only needs to fix
    // the link and positioning.
    self endon("disconnect");
    self endon("StopUFO");
    level endon("game_ended");
    level endon("rainy_shutdown");
    for (;;)
    {
        self waittill("spawned_player");
        if (!isDefined(self.ufoEnabled) || !self.ufoEnabled)
            return;
        // Give the engine one frame to finish its own spawn setup before relinking.
        wait 0.05;
        if (!isDefined(self.ufoEnabled) || !self.ufoEnabled)
            return;
        // ufoEntity is still alive (only deleted on StopUFO). Just relink.
        if (isDefined(self.ufoEntity))
            self playerLinkTo(self.ufoEntity);
    }
}
setMatchTime(minutes)
{
    gameType = getDvar("g_gametype");
    setDvar("scr_" + gameType + "_timelimit", minutes);
}
addMatchTime(minutes)
{
    gameType = getDvar("g_gametype");
    timelimitDvar = "scr_" + gameType + "_timelimit";
    current = getDvarInt(timelimitDvar);
    if (current <= 0)
        current = 0;
    newTime = current + minutes;
    setDvar(timelimitDvar, newTime);
    // Called from settime rows 1 (white), 2 (cyan), 3 (white) - self.menuIndex still
    // holds whichever row triggered this, so use it directly to match that row's color.
    unitLabel = "Minutes";
    if (minutes == 1)
        unitLabel = "Minute";
    if (self.menuIndex == 2)
        self thread rainyShowRaisedMessage("^5Added " + minutes + " " + unitLabel);
    else
        self thread rainyShowRaisedMessage("^7Added " + minutes + " " + unitLabel);
}
rainySetScoreLimit(gt, scoreVal, modeLabel)
{
    // gt: "dm" for FFA, "war" for TDM. scoreVal of 0 = unlimited.
    // Always set the gametype-specific dvar so it sticks across restarts, mirroring
    // how setMatchTime writes scr_<gt>_timelimit. If the player is currently in that
    // gametype, also push the live "scorelimit" dvar (and level.scorelimit) so the
    // change takes effect in the running game immediately.
    setDvar("scr_" + gt + "_scorelimit", scoreVal);
    applied = false;
    if (getDvar("g_gametype") == gt)
    {
        setDvar("scorelimit", scoreVal);
        if (isDefined(level.scorelimit))
            level.scorelimit = scoreVal;
        applied = true;
    }
    if (scoreVal == 0)
        scoreText = "Unlimited";
    else
        scoreText = "" + scoreVal;
    // Called from ffascore/tdmscore rows 0-3. Both pages share the same row parity
    // (0,2 = cyan; 1,3 = white - see their HUD render blocks), so self.menuIndex
    // alone is enough to pick the right color regardless of which page called this.
    rowColor = "^7";
    if (self.menuIndex == 0 || self.menuIndex == 2)
        rowColor = "^5";
    if (applied)
        self thread rainyShowRaisedMessage(rowColor + modeLabel + " Score Set To " + rowColor + scoreText);
    else
        self thread rainyShowRaisedMessage(rowColor + modeLabel + " Score Set To " + rowColor + scoreText + " ^7(applies when playing " + modeLabel + ")");
}
fastLastFFA()
{
    if (getDvar("g_gametype") != "dm")
    {
        self thread rainyShowRaisedMessage("^7Fast Last FFA only works in FFA");
        return;
    }
    scoreLimit = getDvarInt("scr_dm_scorelimit");
    if (scoreLimit <= 1)
        scoreLimit = 30;
    lastScore = scoreLimit - 1;
    if (lastScore < 1)
        lastScore = 29;
    self.pers["score"] = lastScore;
    self.pers["kills"] = lastScore;
    self.score = lastScore;
    self.kills = lastScore;
    self.pers["score"] = lastScore;
    self.pers["kills"] = lastScore;
    self.score = lastScore;
    self.kills = lastScore;
    self thread rainyShowRaisedMessage("^7Fast Last FFA: " + lastScore + " kills - pull up scoreboard to update");
}
resetScoreFFA()
{
    // Opposite of fastLastFFA: zero out the host/owner's own score back to 0.
    if (getDvar("g_gametype") != "dm")
    {
        self thread rainyShowRaisedMessage("^7Reset Score FFA only works in FFA");
        return;
    }
    self.pers["score"] = 0;
    self.pers["kills"] = 0;
    self.score = 0;
    self.kills = 0;
    self thread rainyShowRaisedMessage("^7Reset Score FFA: 0 kills - pull up scoreboard to update");
}
fastLastTDM()
{
    if (getDvar("g_gametype") != "war")
    {
        self thread rainyShowRaisedMessage("^5Fast Last TDM only works in TDM");
        return;
    }
    scoreLimit = getDvarInt("scr_war_scorelimit");
    if (scoreLimit <= 1)
        scoreLimit = 7500;
    lastScore = scoreLimit - 100;
    if (lastScore < 0)
        lastScore = 0;
    myTeam = self.pers["team"];
    if (!isDefined(myTeam) || myTeam == "")
        myTeam = "allies";
    setTeamScore(myTeam, lastScore);
    game["teamScores"][myTeam] = lastScore;
    self thread rainyShowRaisedMessage("^5Fast Last TDM: " + myTeam + " at " + lastScore);
}
/*
    TDM only has two teams (allies/axis). Given the host's own team, this returns
    the other one - used by the TDM Options "Enemy Team" functions so they always
    target whichever team the host is NOT currently on.
*/
rainyGetOpposingTeam(myTeam)
{
    if (myTeam == "allies")
        return "axis";
    return "allies";
}
/*
    TDM Options - Friendly Team Last: identical effect to fastLastTDM (sets the
    host's own team one increment below the score limit), kept as its own function
    so it lives under the TDM Options submenu alongside its Enemy Team counterpart.
*/
friendlyTeamLastTDM()
{
    if (getDvar("g_gametype") != "war")
    {
        self thread rainyShowRaisedMessage("^7Friendly Team Last only works in TDM");
        return;
    }
    scoreLimit = getDvarInt("scr_war_scorelimit");
    if (scoreLimit <= 1)
        scoreLimit = 7500;
    lastScore = scoreLimit - 100;
    if (lastScore < 0)
        lastScore = 0;
    myTeam = self.pers["team"];
    if (!isDefined(myTeam) || myTeam == "")
        myTeam = "allies";
    setTeamScore(myTeam, lastScore);
    game["teamScores"][myTeam] = lastScore;
    self thread rainyShowRaisedMessage("^7Friendly Team Last: " + myTeam + " at " + lastScore);
}
/*
    TDM Options - Enemy Team Last: same fast-last effect as Friendly Team Last, but
    targets whichever team the host is NOT on.
*/
enemyTeamLastTDM()
{
    if (getDvar("g_gametype") != "war")
    {
        self thread rainyShowRaisedMessage("^5Enemy Team Last only works in TDM");
        return;
    }
    scoreLimit = getDvarInt("scr_war_scorelimit");
    if (scoreLimit <= 1)
        scoreLimit = 7500;
    lastScore = scoreLimit - 100;
    if (lastScore < 0)
        lastScore = 0;
    myTeam = self.pers["team"];
    if (!isDefined(myTeam) || myTeam == "")
        myTeam = "allies";
    enemyTeam = rainyGetOpposingTeam(myTeam);
    setTeamScore(enemyTeam, lastScore);
    game["teamScores"][enemyTeam] = lastScore;
    self thread rainyShowRaisedMessage("^5Enemy Team Last: " + enemyTeam + " at " + lastScore);
}
/*
    TDM Options - Reset Friendly Score: zeroes out the host's own TDM team score.
    Mirrors resetScoreFFA's "set back to 0" approach, just for team score instead of
    individual player score.
*/
resetFriendlyScoreTDM()
{
    if (getDvar("g_gametype") != "war")
    {
        self thread rainyShowRaisedMessage("^7Reset Friendly Score only works in TDM");
        return;
    }
    myTeam = self.pers["team"];
    if (!isDefined(myTeam) || myTeam == "")
        myTeam = "allies";
    setTeamScore(myTeam, 0);
    game["teamScores"][myTeam] = 0;
    self thread rainyShowRaisedMessage("^7Reset Friendly Score: " + myTeam + " at 0");
}
/*
    TDM Options - Reset Enemy Score: same as Reset Friendly Score, but targets
    whichever team the host is NOT on.
*/
resetEnemyScoreTDM()
{
    if (getDvar("g_gametype") != "war")
    {
        self thread rainyShowRaisedMessage("^5Reset Enemy Score only works in TDM");
        return;
    }
    myTeam = self.pers["team"];
    if (!isDefined(myTeam) || myTeam == "")
        myTeam = "allies";
    enemyTeam = rainyGetOpposingTeam(myTeam);
    setTeamScore(enemyTeam, 0);
    game["teamScores"][enemyTeam] = 0;
    self thread rainyShowRaisedMessage("^5Reset Enemy Score: " + enemyTeam + " at 0");
}
savePosition()
{
    // No UFO guard needed here - this only reads self.origin/self.angles, which the
    // engine keeps accurate for a playerLinkTo'd entity (that's the whole point of
    // linking), unlike loadPosition which writes position/velocity and has to
    // actually break the UFO link first to avoid fighting it.
    self.savedOrigin = self.origin;
    self.savedAngles = self.angles;
    self.hasSavedPos = true;
    self thread rainyShowRaisedMessage("^7Position Saved");
}
loadPosition()
{
    // UFO is a standing-only bind (see ufoBindMonitor) and must never be
    // touched by crouch+Dpad-down (this function) in either direction -
    // loadPosition previously tore UFO down whenever self.ufoEnabled was
    // true, which silently turned UFO off as a side effect of crouching to
    // load. UFO mode's enabled state is still never touched here.
    //
    // However, SetOrigin alone DOES need a brief unlink while in UFO: an active
    // playerLinkTo re-asserts the player's position relative to self.ufoEntity
    // every frame, which was fighting the SetOrigin call below and making the
    // load look like it "offset relative to current position" instead of
    // actually landing at the saved spot. Fix mirrors the same unlink/move/
    // relink pattern already used elsewhere in this file for the same reason
    // (see spawnPlatformAtCrosshair) - unlink, write the saved position to BOTH
    // the player and the ufoEntity itself (so there's no leftover offset once
    // relinked), then relink. self.ufoEnabled and self.ufoEntity are left fully
    // intact throughout, so the player keeps flying after the load instead of
    // UFO silently dropping.
    if (isDefined(self.hasSavedPos) && self.hasSavedPos)
    {
        inUfo = isDefined(self.ufoEnabled) && self.ufoEnabled;
        if (inUfo)
            self unlink();
        self SetOrigin(self.savedOrigin);
        self SetPlayerAngles(self.savedAngles);
        self SetVelocity((0, 0, 0));
        if (inUfo && isDefined(self.ufoEntity))
        {
            self.ufoEntity.origin = self.savedOrigin;
            self.ufoEntity.angles = self.savedAngles;
            self playerLinkTo(self.ufoEntity);
        }
        // Always come back standing even though the load hotkey is bound to crouch.
        self thread rainyForceStandOnLoad();
        self thread rainyShowRaisedMessage("^5Position Loaded");
    }
    else
    {
        self thread rainyShowRaisedMessage("^5No Saved Position");
    }
}
rainyForceStandOnLoad()
{
    self endon("disconnect");
    // Force the player upright after a load. Repeating setStance briefly overrides
    // the crouch button if it's still held from the load hotkey; after the short window
    // the player can crouch/prone normally again.
    for (i = 0; i < 6; i++)
    {
        self setStance("stand");
        wait 0.12;
    }
}
rainyBlockUfoBindBriefly()
{
    // Crouch + D-pad load can force the player back to "stand" immediately after
    // loading. Because the UFO bind watches the same D-pad event, briefly blocking
    // UFO here prevents that same press from being re-read as Standing + D-pad.
    self.rainyBlockUfoBind = true;
    self notify("rainy_ufo_bind_block_refresh");
    self thread rainyClearUfoBindBlock();
}
rainyClearUfoBindBlock()
{
    self endon("disconnect");
    self endon("rainy_ufo_bind_block_refresh");
    level endon("game_ended");
    level endon("rainy_shutdown");

    wait 0.6;
    self.rainyBlockUfoBind = false;
}
saveLoadBindMonitor()
{
    self endon("disconnect");
    level endon("game_ended");
    level endon("rainy_shutdown");
    self notifyonplayercommand("ts_save_load_dpad_down", "+actionslot 2");
    for (;;)
    {
        self waittill("ts_save_load_dpad_down");
        if (isDefined(self.menuOpen) && self.menuOpen)
            continue;
        rainyStance = self GetStance();
        if (rainyStance == "prone")
        {
            self savePosition();
            wait 0.5;
        }
        else if (rainyStance == "crouch")
        {
            self rainyBlockUfoBindBriefly();
            self loadPosition();
            wait 0.5;
        }
    }
}
/*
    Shared body for the "Restart Game" menu action.
*/
rainyRestartGame()
{
    self closeMenuHud();
    rainyResetTransientSettingsAllPlayers();
    self thread rainyShowRaisedMessage("^5Restarting Game...");
    wait 0.3;
    map_restart(false);
}
/*
    Shared body for the "Instant End Game" menu action.
*/
rainyInstantEndGame()
{
    self closeMenuHud();
    rainyResetTransientSettingsAllPlayers();
    self thread rainyShowRaisedMessage("^7Instant End Game");
    wait 0.3;
    exitLevel(false);
}
