Config = Config or {}

Config.InviteUrl = 'https://discord.gg/cnbhkHphay'
Config.CacheSeconds = 120
Config.RefreshOnlinePlayersSeconds = 300
Config.BlockPendingScreening = true
Config.FailClosed = true

-- Zet whitelist alleen aan nadat de Discord-bot, server-ID en rollen goed zijn ingesteld.
Config.RequireGuildMembership = true
Config.RequireWhitelistRole = false
Config.WhitelistRoleKeys = {
    whitelisted = true,
    owner = true,
    directie = true,
    head_staff = true,
    administrator = true,
}

-- Rollen worden exact op naam gezocht. Dubbele Discord-rolnamen worden uit veiligheid geweigerd.
-- principalGroups worden alleen tijdelijk voor de actieve FiveM-sessie gekoppeld.
Config.Roles = {
    { key = 'owner', name = 'Eigenaar', principalGroups = { 'group.admin' }, whitelist = true },
    { key = 'directie', name = 'HexTactics Directie', principalGroups = { 'group.admin' }, whitelist = true },
    { key = 'lead_developer', name = 'Lead Developer', principalGroups = { 'group.admin', 'group.ht_developer' } },
    { key = 'developer', name = 'Developer', principalGroups = { 'group.ht_developer' } },
    { key = 'community_manager', name = 'Community Manager', principalGroups = { 'group.ht_staff' } },
    { key = 'head_staff', name = 'Head Staff', principalGroups = { 'group.admin', 'group.ht_staff' }, whitelist = true },
    { key = 'administrator', name = 'Administrator', principalGroups = { 'group.admin', 'group.ht_staff' }, whitelist = true },
    { key = 'moderator', name = 'Moderator', principalGroups = { 'group.ht_moderator', 'group.ht_staff' } },
    { key = 'support', name = 'Support', principalGroups = { 'group.ht_support', 'group.ht_staff' } },
    { key = 'beta_tester', name = 'Beta Tester', principalGroups = { 'group.ht_beta' } },
    { key = 'content_creator', name = 'Content Creator', principalGroups = { 'group.ht_creator' } },
    { key = 'police', name = 'Politie', principalGroups = { 'group.ht_police' } },
    { key = 'ambulance', name = 'Ambulance', principalGroups = { 'group.ht_ambulance' } },
    { key = 'anwb', name = 'ANWB', principalGroups = { 'group.ht_anwb' } },
    { key = 'business_owner', name = 'Bedrijfseigenaar', principalGroups = { 'group.ht_business' } },
    { key = 'whitelisted', name = 'Whitelisted', principalGroups = { 'group.ht_whitelisted' }, whitelist = true },
    { key = 'citizen', name = 'Burger', principalGroups = {} },
    { key = 'announcements', name = 'Mededelingen', principalGroups = {} },
    { key = 'unverified', name = 'Niet geverifieerd', principalGroups = {} },
}

-- Veilige provisioning: /discordsetup maakt alleen ontbrekende rollen/kanalen aan.
-- Bestaande rollen/kanalen worden nooit verwijderd, hernoemd of overschreven.
Config.Provisioning = {
    enabled = true,
    roleDefaults = {
        permissions = '0',
        hoist = false,
        mentionable = false,
    },
    categories = {
        {
            key = 'start',
            name = 'START',
            channels = {
                { key = 'welcome', name = 'welkom', type = 'text', topic = 'Welkom bij Delfzijl Roleplay.' },
                { key = 'rules', name = 'regels', type = 'text', topic = 'Server- en communityregels.' },
                { key = 'announcements', name = 'mededelingen', type = 'text', topic = 'Officiële mededelingen.' },
                { key = 'server_status', name = 'server-status', type = 'text', topic = 'Automatische FiveM-serverstatus.' },
                { key = 'role_select', name = 'rollen-kiezen', type = 'text', topic = 'Kies jouw communityrollen.' },
            },
        },
        {
            key = 'community',
            name = 'COMMUNITY',
            channels = {
                { key = 'general', name = 'algemene-chat', type = 'text' },
                { key = 'media', name = 'media', type = 'text' },
                { key = 'suggestions', name = 'suggesties', type = 'text' },
                { key = 'support_public', name = 'hulp-en-support', type = 'text' },
                { key = 'lounge', name = 'Lounge', type = 'voice' },
            },
        },
        {
            key = 'applications',
            name = 'AANVRAGEN',
            channels = {
                { key = 'whitelist_apply', name = 'whitelist-aanvraag', type = 'text' },
                { key = 'police_apply', name = 'politie-sollicitatie', type = 'text' },
                { key = 'ambulance_apply', name = 'ambulance-sollicitatie', type = 'text' },
                { key = 'anwb_apply', name = 'anwb-sollicitatie', type = 'text' },
                { key = 'business_apply', name = 'bedrijf-aanvraag', type = 'text' },
            },
        },
        {
            key = 'development',
            name = 'DEVELOPMENT',
            allowedRoles = { 'owner', 'directie', 'lead_developer', 'developer', 'beta_tester' },
            channels = {
                { key = 'development_chat', name = 'development-chat', type = 'text' },
                { key = 'updates', name = 'updates', type = 'text' },
                { key = 'changelog', name = 'changelog', type = 'text' },
                { key = 'bug_reports', name = 'bug-meldingen', type = 'text' },
            },
        },
        {
            key = 'staff',
            name = 'STAFF',
            allowedRoles = { 'owner', 'directie', 'community_manager', 'head_staff', 'administrator', 'moderator', 'support' },
            channels = {
                { key = 'staff_chat', name = 'staff-chat', type = 'text' },
                { key = 'staff_announcements', name = 'staff-mededelingen', type = 'text' },
                { key = 'reports', name = 'reports', type = 'text' },
                { key = 'bans', name = 'bans', type = 'text' },
                { key = 'staff_logs', name = 'staff-logs', type = 'text' },
                { key = 'staff_voice', name = 'Staff Spraak', type = 'voice' },
            },
        },
        {
            key = 'police',
            name = 'POLITIE',
            allowedRoles = { 'owner', 'directie', 'head_staff', 'administrator', 'police' },
            channels = {
                { key = 'police_chat', name = 'politie-chat', type = 'text' },
                { key = 'police_announcements', name = 'politie-mededelingen', type = 'text' },
                { key = 'police_logs', name = 'politie-logs', type = 'text' },
                { key = 'police_voice', name = 'Politie Spraak', type = 'voice' },
            },
        },
        {
            key = 'ambulance',
            name = 'AMBULANCE',
            allowedRoles = { 'owner', 'directie', 'head_staff', 'administrator', 'ambulance' },
            channels = {
                { key = 'ambulance_chat', name = 'ambulance-chat', type = 'text' },
                { key = 'ambulance_announcements', name = 'ambulance-mededelingen', type = 'text' },
                { key = 'ambulance_logs', name = 'ambulance-logs', type = 'text' },
                { key = 'ambulance_voice', name = 'Ambulance Spraak', type = 'voice' },
            },
        },
        {
            key = 'anwb',
            name = 'ANWB',
            allowedRoles = { 'owner', 'directie', 'head_staff', 'administrator', 'anwb' },
            channels = {
                { key = 'anwb_chat', name = 'anwb-chat', type = 'text' },
                { key = 'anwb_announcements', name = 'anwb-mededelingen', type = 'text' },
                { key = 'anwb_logs', name = 'anwb-logs', type = 'text' },
                { key = 'anwb_voice', name = 'ANWB Spraak', type = 'voice' },
            },
        },
        {
            key = 'logs',
            name = 'LOGS',
            allowedRoles = { 'owner', 'directie', 'lead_developer', 'developer', 'head_staff', 'administrator' },
            channels = {
                { key = 'join_leave', name = 'joins-leaves', type = 'text' },
                { key = 'server_logs', name = 'server-logs', type = 'text' },
                { key = 'economy_logs', name = 'economie-logs', type = 'text' },
                { key = 'crime_logs', name = 'crime-logs', type = 'text' },
                { key = 'vehicle_logs', name = 'voertuig-logs', type = 'text' },
                { key = 'security_logs', name = 'security-logs', type = 'text' },
            },
        },
    },
}
