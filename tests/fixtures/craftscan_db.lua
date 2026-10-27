-- Synthetic CraftScan_DB (CraftScan 1.6.3 shape, spec §10.2; no names from a real file): the tests'
-- and the sim's --craftscan input. Recipe IDs 9001-9005 are the sim's stubbed recipes.
--   Scanalt-OwnRealm     this account, connected group "_1": Blacksmithing main crafter; 9004 on,
--                        9005 off, 9001 unlearned, 777777 unknown to the client, "x" malformed
--   Linked-OwnRealm      a linked account's character (foreign sourceID): never imported
--   Nosource-KelThuzad   no sourceID (this account), legacy key without the realm's apostrophe;
--                        Blacksmithing scanning switched off, so its 9003 comes in muted
--   Old-Legacyrealm      named realm, legacy records (no scan_state): 9003 enabled, 9005 not
return {
  settings = {
    my_uuid = "uuid-mine",
    greeting = {
      GREETING_I_CAN_CRAFT_ITEM = "Hey, {crafter} makes {item}",
      GREETING_I_HAVE_PROF = "I do {profession_link}, need anything?",
      GREETING_ALT_SUFFIX = "(alt)",
      GREETING_BUSY = "Busy, sorry",
      rev = 3,
    },
  },
  connected_realms = { OwnRealm = "_1", PartnerRealm = "_1", ["Kel'Thuzad"] = "_2" },
  realms = {
    _1 = {
      characters = {
        ["Scanalt-OwnRealm"] = {
          sourceID = "uuid-mine",
          parent_professions = { [164] = { primary_crafter = true, scanning_enabled = true } },
          professions = {
            [2872] = {
              parentProfID = 164,
              recipes = {
                [9004] = { scan_state = 2 },
                [9005] = { scan_state = 3 },
                [9001] = { scan_state = 4 },
                [777777] = { scan_state = 2 },
                x = { scan_state = 2 },
              },
            },
          },
        },
        ["Linked-OwnRealm"] = {
          sourceID = "uuid-other",
          parent_professions = {},
          professions = { [2872] = { parentProfID = 164, recipes = { [9001] = { scan_state = 2 } } } },
        },
      },
      customers = {},
      listed_orders = {},
      analytics = {},
    },
    _2 = {
      characters = {
        ["Nosource-KelThuzad"] = {
          parent_professions = { [164] = { scanning_enabled = false } },
          professions = { [2873] = { parentProfID = 164, recipes = { [9003] = { scan_state = 2 } } } },
        },
      },
      customers = {},
      listed_orders = {},
      analytics = {},
    },
    Legacyrealm = {
      characters = {
        ["Old-Legacyrealm"] = {
          parent_professions = {},
          professions = {
            [2874] = { parentProfID = 164, all_enabled = false, recipes = { [9003] = { enabled = true }, [9005] = {} } },
          },
        },
      },
      customers = {},
      listed_orders = {},
    },
    _9 = "not a realm",
  },
}
