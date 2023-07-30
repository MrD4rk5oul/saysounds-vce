#include <sourcemod>
#include <sdktools>
#include <clientprefs>
#include <VoiceInjector>
#include <sdktools_functions>
#include <sdktools_voice>

#undef REQUIRE_PLUGIN
#include <adminmenu>

#pragma semicolon 1

#define PLUGIN_VERSION			"1.0.0"
#define SOURCETV_DEFAULT_CUSTOM_NAME	"Audio Output"

#define SAYSOUND_FLAG_ADMIN		(1 << 0)

#define SAYSOUND_TRIGGER_SIZE		64

#define TIME_BETWEEN_BUFFERS		0.11
#define BUFFER_SIZE			1024
#define SOUNDS_PER_PAGE			15

enum
{
  SAYSOUND_CLIENT = 0,
  SAYSOUND_DONOR,
  SAYSOUND_ADMIN
}
new g_access[MAXPLAYERS+1];

enum
{
  SAYSOUND_PREF_DISABLED = 0,
  SAYSOUND_PREF_BANNED
}
new g_clientprefs[MAXPLAYERS+1][3];

new g_serial;
new g_soundcount[MAXPLAYERS+1];
new Float:gf_LastSaysound[MAXPLAYERS+1];

public Plugin:myinfo = 
{
  name = "Say Sounds (Voice Chat Edition)",
  author = "Locke, Mathx, friagram",
  description = "Plays sounds through Voice Chat",
  version = PLUGIN_VERSION,
  url = ""
};

new Handle:gh_flags, Handle:gh_trigger, Handle:gh_paths, Handle:gh_recentsounds;
new Handle:gh_cookie;
new Handle:gh_menu, Handle:gh_adminmenu;
new Handle:hAdminMenu = INVALID_HANDLE;

new bool:gb_enabled;
new g_saysound_limit[3];
new Float:gf_saysound_delay[3];
new bool:gb_preventspam[3];
new bool:gb_saysound_round;
new bool:gb_saysound_sentence;
new bool:gb_saysound_blocktrigger;
char gs_sourcetv_custom_name[33];
new g_saysound_excludecount;
new bool:gb_playingame;

File g_currentFile;
int g_sourceTVClientUserIdx = -1;
float g_TimeToSendNextPackets;

public OnPluginStart()
{
  // ***Load Translations **
  LoadTranslations("common.phrases");

  CreateConVar("sm_saysounds_redux_version", PLUGIN_VERSION, "Say Sounds Version", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);

  decl Handle:cvar;
  HookConVarChange(cvar = CreateConVar("sm_saysounds_enable","1","Turns Sounds On/Off", 0, true, 0.0, true, 1.0), Cvar_EnableChanged);
  gb_enabled = GetConVarBool(cvar);

  HookConVarChange(cvar = CreateConVar("sm_saysounds_sound_limit","10","Maximum sounds per person (0 for unlimited)", 0, true, 0.0, false, 0.0), Cvar_LimitChanged);
  g_saysound_limit[0] = GetConVarInt(cvar);
  
  HookConVarChange(cvar = CreateConVar("sm_saysounds_donor_limit","15","Maximum sounds for saysounds_donor (0 for unlimited)", 0, true, 0.0, false, 0.0), Cvar_DonorLimitChanged);
  g_saysound_limit[1] = GetConVarInt(cvar);

  HookConVarChange(cvar = CreateConVar("sm_saysounds_admin_limit","0","Maximum sounds per saysounds_admin (0 for unlimited)", 0, true, 0.0, false, 0.0), Cvar_AdminLimitChanged);
  g_saysound_limit[2] = GetConVarInt(cvar);

  HookConVarChange(cvar = CreateConVar("sm_saysounds_sound_delay","5.0","Time between each sound trigger, 0.0 to disable checking", 0, true, 0.0, false, 0.0), Cvar_DelayChanged);
  gf_saysound_delay[0] = GetConVarFloat(cvar);

  HookConVarChange(cvar = CreateConVar("sm_saysounds_donor_delay","3.0","User flags to bypass the Time between sounds check", 0, true, 0.0, false, 0.0), Cvar_DonorDelayChanged);
  gf_saysound_delay[1] = GetConVarFloat(cvar);

  HookConVarChange(cvar = CreateConVar("sm_saysounds_admin_delay","1.0","User flags to bypass the Time between sounds check", 0, true, 0.0, false, 0.0), Cvar_AdminDelayChanged);
  gf_saysound_delay[2] = GetConVarFloat(cvar);

  HookConVarChange(cvar = CreateConVar("sm_saysounds_round", "0", "If set, sm_saysoundhe_sound_limit is the limit per round instead of per map", 0, true, 0.0, true, 1.0), Cvar_RoundChanged);
  gb_saysound_round = GetConVarBool(cvar);

  HookConVarChange(cvar = CreateConVar("sm_saysounds_sound_sentence", "1", "When set, will trigger sounds if keyword is embedded in a sentence", 0, true, 0.0, true, 1.0), Cvar_SentenceChanged);
  gb_saysound_sentence = GetConVarBool(cvar);

  HookConVarChange(cvar = CreateConVar("sm_saysounds_block_trigger", "0", "If set, block the sound trigger to be displayed in the chat window", 0, true, 0.0, true, 1.0), Cvar_BlockTriggerChanged);
  gb_saysound_blocktrigger = GetConVarBool(cvar);

  HookConVarChange(cvar = CreateConVar("sm_saysounds_exclude", "2", "Number of sounds that must be different before this sound can be replayed", 0, true, 0.0, false, 0.0), Cvar_ExcludeChanged);
  g_saysound_excludecount = GetConVarInt(cvar);

  HookConVarChange(cvar = CreateConVar("sm_saysounds_exclude_client", "1", "If set, clients obey exclude count", 0, true, 0.0, true, 1.0), Cvar_SpamClientChanged);
  gb_preventspam[0] = GetConVarBool(cvar);

  HookConVarChange(cvar = CreateConVar("sm_saysounds_exclude_donor", "1", "If set, donors obey exclude count", 0, true, 0.0, true, 1.0), Cvar_SpamDonorChanged);
  gb_preventspam[1] = GetConVarBool(cvar);

  HookConVarChange(cvar = CreateConVar("sm_saysounds_exclude_admin", "0", "If set, admins obey exclude count", 0, true, 0.0, true, 1.0), Cvar_SpamAdminChanged);
  gb_preventspam[2] = GetConVarBool(cvar);

  HookConVarChange(cvar = CreateConVar("sm_saysounds_playingame","0.0","Play as an emit sound or direct (0 / 1)", 0,true, 0.0,true,1.0), Cvar_PlayIngameChanged);
  gb_playingame = GetConVarBool(cvar);

  HookConVarChange(cvar = CreateConVar("sm_saysounds_custom_name",SOURCETV_DEFAULT_CUSTOM_NAME,"Custom name for the SourceTV client. Max. 32 Chars", 0), Cvar_SourceTVCustomNameChanged);
  GetConVarString(cvar, gs_sourcetv_custom_name, 33);

  gh_cookie = RegClientCookie("saysounds_pref", "saysounds data", CookieAccess_Protected);
  SetCookieMenuItem(SaysoundClientPref, 0, "Say Sounds Settings");

  RegAdminCmd("sm_sound_ban", Command_Sound_Ban, ADMFLAG_BAN, "sm_sound_ban <user> : Bans a player from using sounds");
  RegAdminCmd("sm_sound_reset", Command_Sound_Reset, ADMFLAG_GENERIC, "sm_sound_reset <user | all> : Resets sound quota for user, or everyone if all");
  RegAdminCmd("sm_refresh_sounds", Command_Sounds_Refresh, ADMFLAG_GENERIC, "Refresh Saysounds list");
  RegAdminCmd("sm_output_name", Command_Sounds_Refresh, ADMFLAG_ROOT, "sm_output_name '<name>' : Set output name");
  RegConsoleCmd("sm_soundlist", Command_Sound_Menu, "Display a menu sounds to play");
  RegConsoleCmd("sm_soundlist2", Command_ListSounds, "Output a list of sounds to the console");
  RegConsoleCmd("sm_sounds", Command_Sound_Toggle, "Toggle Saysounds");

  AddCommandListener(Command_Say, "say");
  AddCommandListener(Command_Say, "say2");
  AddCommandListener(Command_Say, "say_team");

  HookEvent("teamplay_round_start", Event_RoundStart);

  new Handle:topmenu;
  if (LibraryExists("adminmenu") && ((topmenu = GetAdminTopMenu()) != INVALID_HANDLE))
  {
    OnAdminMenuReady(topmenu);
  }

  SetupSourceTVClient();
  PrepareSounds();
  
  for(new client = 1; client <= MaxClients; client++)
  {
    if(IsClientConnected(client) && IsClientAuthorized(client) && !IsFakeClient(client))
    {
      OnClientPostAdminCheck(client);
      if(AreClientCookiesCached(client))
      {
        OnClientCookiesCached(client);
      }
    }
  }
}

public OnClientConnected()
{
  if (g_sourceTVClientUserIdx == -1)
  {
    SetupSourceTVClient();
  }
}

public OnMapStart()
{
  g_TimeToSendNextPackets = GetEngineTime();
  ResetClients();
  SetupSourceTVClient();
}

public OnGameFrame()
{
  if(g_TimeToSendNextPackets > GetEngineTime()) {
    return;
  }
  SendNextVoicePackets();
}

void SetupSourceTVClient()
{
  if (g_sourceTVClientUserIdx == -1)
  {
    int cliCount = GetClientCount(false);
    for (int i = 1; i < cliCount; i++)
    {
      if (IsClientSourceTV(i))
      {
        g_sourceTVClientUserIdx = i;
        ChangeSourceTVName();
        return;
      }
    }
  }
}

public ChangeSourceTVName()
{
  if (g_sourceTVClientUserIdx != -1)
  {
    SetClientName(g_sourceTVClientUserIdx, gs_sourcetv_custom_name);
  }
}

public Action Command_ListSounds(int client, int args)
{
  int page;
  int arrSize = GetArraySize(gh_trigger);
  int maxPage = 1 + (arrSize / SOUNDS_PER_PAGE);

  if (!GetCmdArgIntEx(1, page))
    page = 1;

  if (page < 1)
    page = 1;
  else if (page > maxPage)
    page = maxPage;

  if (GetCmdReplySource() == SM_REPLY_TO_CHAT)
    ReplyToCommand(client, "[SM] Sound List outputted to console.");

  int start = (page - 1) * SOUNDS_PER_PAGE;
  int end   = (page) * SOUNDS_PER_PAGE;
  char triggerNames[1024];
  end = end > arrSize ? arrSize : end;

  char[] response = 
    "[SM] Available Sounds (Page %d/%d):\n\
    \n\
    =======================\n\
    %s\
    =======================";

  int currentIdx = 0;

  for (int i = start; i < end; i++)
  {
    currentIdx += GetArrayString(gh_trigger, i, triggerNames[currentIdx], SAYSOUND_TRIGGER_SIZE);
    triggerNames[currentIdx] = '\n';
    currentIdx++;
  }
  triggerNames[currentIdx] = 0;

  PrintToConsole(client, response, page, maxPage, triggerNames);

  return Plugin_Handled;
}

public Cvar_EnableChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
  gb_enabled = bool:StringToInt(newValue);
}
public Cvar_LimitChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
  g_saysound_limit[0] = StringToInt(newValue);
}
public Cvar_DonorLimitChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
  g_saysound_limit[1] = StringToInt(newValue);
}
public Cvar_AdminLimitChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
  g_saysound_limit[2] = StringToInt(newValue);
}
public Cvar_DelayChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
  gf_saysound_delay[0] = StringToFloat(newValue);
}
public Cvar_DonorDelayChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
  gf_saysound_delay[1] = StringToFloat(newValue);
}
public Cvar_AdminDelayChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
  gf_saysound_delay[2] = StringToFloat(newValue);
}
public Cvar_RoundChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
  gb_saysound_round = bool:StringToInt(newValue);
}
public Cvar_SentenceChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
  gb_saysound_sentence = bool:StringToInt(newValue);
}
public Cvar_BlockTriggerChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
  gb_saysound_blocktrigger = bool:StringToInt(newValue);
}
public Cvar_ExcludeChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
  g_saysound_excludecount = StringToInt(newValue);
  ClearArray(gh_recentsounds);
}
public Cvar_SpamClientChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
  gb_preventspam[0] = bool:StringToInt(newValue);
}
public Cvar_SpamDonorChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
  gb_preventspam[1] = bool:StringToInt(newValue);
}
public Cvar_SpamAdminChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
  gb_preventspam[2] = bool:StringToInt(newValue);
}
public Cvar_SourceTVCustomNameChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
  GetConVarString(convar, gs_sourcetv_custom_name, 33);
  gs_sourcetv_custom_name[32] = 0;
  ChangeSourceTVName();
}

public Cvar_PlayIngameChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
  gb_playingame = bool:StringToInt(newValue);
  if(gb_playingame)
  {
    PrecacheSounds();
  }
}

public OnClientCookiesCached(int client)
{
  if(!IsFakeClient(client))
  {
    decl String:cookie[32];
    new String:segment[4][4];
    GetClientCookie(client, gh_cookie, cookie, sizeof(cookie));
    ExplodeString(cookie, ";", segment, 4, 4);

    g_clientprefs[client][SAYSOUND_PREF_DISABLED] = bool:StringToInt(segment[0]);
    g_clientprefs[client][SAYSOUND_PREF_BANNED] = bool:StringToInt(segment[1]);

    if(StringToInt(segment[2]) == g_serial)
    {
      g_soundcount[client] = StringToInt(segment[3]);
    }
    else
    {
      g_soundcount[client] = 0;
    }

    SetClientCanHearSaysounds(client, !g_clientprefs[client][SAYSOUND_PREF_DISABLED]);
  }
}

public SetClientCanHearSaysounds(int client, bool canHear)
{
  if (g_sourceTVClientUserIdx != -1 && !IsFakeClient(client))
  {
    ListenOverride loCanHear = canHear ? Listen_Yes : Listen_No;
    
    SetListenOverride(client, g_sourceTVClientUserIdx, loCanHear);

    ReplyToCommand(client, "[SM] %N is now %s", g_sourceTVClientUserIdx, canHear ? "unmuted" : "muted");
  }
}

public OnClientDisconnect(client)
{
  if(!IsFakeClient(client))
  {
    StoreClientCookies(client);
  }
}

void StoreClientCookies(client)
{
  if(AreClientCookiesCached(client))
  {
    decl String:cookie[32];
    FormatEx(cookie, sizeof(cookie), "%d;%d;%d;%d",
      g_clientprefs[client][SAYSOUND_PREF_DISABLED], g_clientprefs[client][SAYSOUND_PREF_BANNED],
      g_serial, g_soundcount[client]);

    SetClientCookie(client, gh_cookie, cookie);
  }
}

void ResetClients()
{
  g_serial++;
  ClearArray(gh_recentsounds);
  if (gb_saysound_round)
  {
    for (new client = 1; client <= MaxClients; client++)
    {
      g_soundcount[client] = 0;
    }
  }
}

void PrecacheSounds()
{
  decl String:soundfile[PLATFORM_MAX_PATH];
  decl Handle:hpath;
  
  for(new i = GetArraySize(gh_paths) - 1; i >= 0; i--)
  {
    hpath = GetArrayCell(gh_paths, i);

    for(new k = GetArraySize(hpath) - 1; k >= 0; k--)
    {
      GetArrayString(hpath, k, soundfile, sizeof(soundfile));
      if(gb_playingame)
      {
        PrecacheSound(soundfile, true);
      }
    }
  }
}

void LoadSoundList()
{
  ClearArray(gh_flags);
  ClearArray(gh_trigger);
  ClearArray(gh_paths);

  if (gh_menu != INVALID_HANDLE)
    RemoveAllMenuItems(gh_menu);

  if (gh_adminmenu != INVALID_HANDLE)
    RemoveAllMenuItems(gh_adminmenu);
  
  decl String:soundlistfile[PLATFORM_MAX_PATH];
  BuildPath(Path_SM,soundlistfile,sizeof(soundlistfile),"configs/saysounds.cfg");
  if(!FileExists(soundlistfile))
  {
    SetFailState("saysounds.cfg not parsed...file doesnt exist!");
  }
  else
  {
    new Handle:listfile = CreateKeyValues("soundlist");
    FileToKeyValues(listfile,soundlistfile);
    KvRewind(listfile);
    if (KvGotoFirstSubKey(listfile))
    {
      gh_menu = CreateMenu(menu_handler);
      gh_adminmenu = CreateMenu(menu_handler);
      
      SetMenuTitle(gh_menu, "Saysounds\n ");
      SetMenuTitle(gh_adminmenu, "Saysounds\n ");
    
      decl String:filelocation[PLATFORM_MAX_PATH], String:item[8], String:trigger[SAYSOUND_TRIGGER_SIZE];
      decl Handle:soundpath;
      decl flags;

      do
      {
        KvGetString(listfile, "file", filelocation, sizeof(filelocation), "");
        if(filelocation[0] != '\0')
        {
          soundpath = CreateArray(ByteCountToCells(PLATFORM_MAX_PATH));
          KvGetSectionName(listfile, trigger, sizeof(trigger));

          flags = 0;
          if(KvGetNum(listfile, "admin", 0))
          {
            flags |= SAYSOUND_FLAG_ADMIN;
            
            AddMenuItem(gh_adminmenu, trigger, trigger);
          }
          else
          {
            AddMenuItem(gh_adminmenu, trigger, trigger);
            AddMenuItem(gh_menu, trigger, trigger);
          }

          PushArrayCell(gh_paths, soundpath);
          PushArrayString(gh_trigger, trigger);
          PushArrayCell(gh_flags, flags);

          PushArrayString(soundpath, filelocation);

          for (new i = 2;; i++)
          {
            FormatEx(item, sizeof(item),  "file%d", i);
            KvGetString(listfile, item, filelocation, sizeof(filelocation), "");
            if (filelocation[0] == '\0')
            {
              break;
            }
            PushArrayString(soundpath, filelocation);
          }
        }
      }
      while (KvGotoNextKey(listfile));
    }
    else
    {
      SetFailState("saysounds.cfg not parsed...No subkeys found!");
    }

    CloseHandle(listfile);
  }
}

void PrepareSounds()
{
  gh_flags = CreateArray();
  gh_trigger = CreateArray(ByteCountToCells(SAYSOUND_TRIGGER_SIZE));
  gh_paths = CreateArray(ByteCountToCells(PLATFORM_MAX_PATH));
  gh_recentsounds = CreateArray();

  LoadSoundList();
}


public Action:Event_RoundStart(Handle:event,const String:name[],bool:dontBroadcast)
{
  ResetClients();

  return Plugin_Continue;
}

public OnClientPostAdminCheck(client)		// I'm not going to bother checking admin rehashing
{
  if(CheckCommandAccess(client, "saysounds_admin", ADMFLAG_CHAT, true))
  {
    g_access[client] = SAYSOUND_ADMIN;
  }
  else if(CheckCommandAccess(client, "saysounds_donor", ADMFLAG_RESERVATION, true))
  {
    g_access[client] = SAYSOUND_DONOR;
  }
  else
  {
    g_access[client] = SAYSOUND_CLIENT;
  }
}

public OnRebuildAdminCache(AdminCachePart:part)
{
    if(part == AdminCache_Admins)
    {
        CreateTimer(1.0, Timer_WaitForAdminCacheReload, _, TIMER_FLAG_NO_MAPCHANGE);
    }
}

public Action:Timer_WaitForAdminCacheReload(Handle:timer)
{
    for(new client = 1; client <= MaxClients; client++)
    {
        if(IsClientConnected(client) && IsClientAuthorized(client) && !IsFakeClient(client))
        {
            OnClientPostAdminCheck(client);
        }
    }
}

public Action:Command_Say(client, const String:command[], argc)
{
  static String:speech[256];
  static startidx;

  if(gb_enabled && !g_clientprefs[client][SAYSOUND_PREF_DISABLED] && !g_clientprefs[client][SAYSOUND_PREF_BANNED])		// enabled, they can emit sounds to others
  {
    if (GetCmdArgString(speech, sizeof(speech)) >= 1)
    {
      startidx = 0;
      
      if (speech[strlen(speech)-1] == '"')
      {
        speech[strlen(speech)-1] = '\0';
        startidx = 1;
      }

      if (strcmp(command, "say2", false) == 0)
      {
        startidx += 4;
      }

      return  Action:AttemptSaySound(client, speech[startidx]);
    }
  }	
  return Plugin_Continue;
}

public Action:AttemptSaySound(client, String:sound[])
{
  static String:buffer[PLATFORM_MAX_PATH];
  static size, flags;
  static Handle:hpath;

  if(g_saysound_limit[g_access[client]])																			// is there a limit, are they at it
  {
    if(g_soundcount[client] >= g_saysound_limit[g_access[client]])
    {
      return Plugin_Continue;
    }
  }

  new Float:time = GetEngineTime();																							// are they experiencing delay
  if(time > gf_LastSaysound[client])
  {
    new bool:adminonly;

    size = GetArraySize(gh_paths);																				// traverse forward
    for(new i; i < size; i++)
    {
      GetArrayString(gh_trigger, i, buffer, sizeof(buffer));
      if((gb_saysound_sentence && StrContains(sound, buffer, false) >= 0) || strcmp(sound, buffer, false) == 0)
      {
        flags = GetArrayCell(gh_flags, i);
        if((flags & SAYSOUND_FLAG_ADMIN) && g_access[client] != SAYSOUND_ADMIN)
        {
          adminonly = true;

          continue;																					// perhaps there is something similar they can use
        }

        if(gb_preventspam[g_access[client]])
        {
          if(FindValueInArray(gh_recentsounds, i) != -1)
          {
            if(client && IsClientInGame(client))
            {
              PrintToChat(client, "[SM] this sound was recently played");
            }
            return Plugin_Continue;
          }
        }

        hpath = GetArrayCell(gh_paths, i);
        GetArrayString(hpath, GetRandomInt(0, GetArraySize(hpath)-1), buffer, sizeof(buffer));

        DoSaySound(buffer);

        if(PushArrayCell(gh_recentsounds, i) >= g_saysound_excludecount)
        {
          RemoveFromArray(gh_recentsounds, 0);
        }

        if(gf_saysound_delay[g_access[client]])
        {
          gf_LastSaysound[client] = time + gf_saysound_delay[g_access[client]];
        }
        
        g_soundcount[client]++;
        DisplayRemainingSounds(client);
        
        if(gb_saysound_blocktrigger)
        {
          return Plugin_Handled;
        }

        return Plugin_Continue;
      }
    }
    
    if(adminonly)
    {
      if(client && IsClientInGame(client))
      {
        PrintToChat(client, "[SM] you do not have access to this sound");
      }
    }
  }

  return Plugin_Continue;
}

void DisplayRemainingSounds(client)
{
  if(g_saysound_limit[g_access[client]])
  {
    if(client && IsClientInGame(client))
    {
      PrintToChat(client, "[SM] you have used %d/%d sounds", g_soundcount[client], g_saysound_limit[g_access[client]]);
    }
  }
}

void DoSaySound(String:soundfile[])
{
  if (g_currentFile)
  {
    CloseCurrentFile();
  }
  g_currentFile = OpenFile(soundfile, "r", true);
  g_currentFile.Seek(48, SEEK_SET);
}

void CloseCurrentFile()
{
  g_currentFile.Close();
  g_currentFile = null;
}

void SendNextVoicePackets()
{
  if ((!g_currentFile) || (g_sourceTVClientUserIdx < 0))
    return;

  int totalSamplesRead = 0;

  for (int i = 0; i < 8; i++)
  {
    char data[BUFFER_SIZE];

    // Since a char = 1 byte and sample = 2 bytes, we divide the count by 2
    
    int samplesRead   =  g_currentFile.ReadString(data, sizeof(data), BUFFER_SIZE) / 2;
    totalSamplesRead += samplesRead;

    if (samplesRead > 0)
    {
      PlayAudioOnVoiceChat(
        GetClientOfUserId(g_sourceTVClientUserIdx),
        samplesRead,
        data
      );
    }
    else
    {
      CloseCurrentFile();
      break;
    }
  }

  if(g_TimeToSendNextPackets < GetEngineTime()) {
    g_TimeToSendNextPackets = GetEngineTime();
  }

  g_TimeToSendNextPackets += float(totalSamplesRead) / 22050.0;
}

public Action Command_Sounds_Refresh(int client, int args)
{
  LoadSoundList();
  ReplyToCommand(client, "[SM] Sound List Refreshed");
  
  return Plugin_Handled;
}

public Action:Command_Sound_Reset(client, args)
{
  if (args < 1)
  {
    ReplyToCommand(client, "[sm] usage: sm_sound_reset <target>");
    return Plugin_Handled;
  }

  new String:arg[64];
  GetCmdArg(1, arg, sizeof(arg));	

  decl String:name[64];
  new bool:isml,clients[MAXPLAYERS+1];
  new count=ProcessTargetString(arg,client,clients,MAXPLAYERS+1,COMMAND_FILTER_CONNECTED|COMMAND_FILTER_NO_BOTS,name,sizeof(name),isml);
  if (count > 0)
  {
    for(new x=0;x<count;x++)
    {
      g_soundcount[clients[x]] = 0;
      DisplayRemainingSounds(clients[x]);
    }
  }
  else
  {
    ReplyToTargetError(client, count);
  }

  return Plugin_Handled;
}

public Action:Command_Sound_Ban(client, args)
{
  if (args < 1)
  {
    ReplyToCommand(client, "[sm] usage: sm_sound_ban <target>");
    return Plugin_Handled;	
  }

  new String:arg[64];
  GetCmdArg(1, arg, sizeof(arg));	

  decl String:name[64];
  new bool:isml,clients[MAXPLAYERS+1];
  new count=ProcessTargetString(arg,client,clients,MAXPLAYERS+1,COMMAND_FILTER_CONNECTED|COMMAND_FILTER_NO_BOTS|COMMAND_FILTER_NO_MULTI,name,sizeof(name),isml);
  if (count == 1)
  {
    g_clientprefs[clients[0]][SAYSOUND_PREF_BANNED] = !g_clientprefs[clients[0]][SAYSOUND_PREF_BANNED];
    ReplyToCommand(client, "[SM] %N ban status set to: %s", clients[0], g_clientprefs[clients[0]][SAYSOUND_PREF_BANNED] ? "banned" : "unbanned");
    
    StoreClientCookies(clients[0]);
  }
  else
  {
    ReplyToTargetError(client, count);
  }

  return Plugin_Handled;
}

public SaysoundClientPref(client, CookieMenuAction:action, any:info, String:buffer[], maxlen)
{
  if (action == CookieMenuAction_SelectOption)
  {
    ShowClientPrefMenu(client);
  }
}

ShowClientPrefMenu(client)
{
  new Handle:menu = CreateMenu(MenuHandlerClientPref);

  SetMenuTitle(menu, "Saysounds\n ");

  AddMenuItem(menu, "", g_clientprefs[client][SAYSOUND_PREF_DISABLED] ? "Saysounds: Disabled" : "Saysounds: Enabled");

  SetMenuExitButton(menu, true);

  DisplayMenu(menu, client, 0);
}

public MenuHandlerClientPref(Handle:menu, MenuAction:action, param1, param2)
{
  if(action == MenuAction_Select)	
  {
    if (param2 == 0)
    {
      g_clientprefs[param1][SAYSOUND_PREF_DISABLED] = !g_clientprefs[param1][SAYSOUND_PREF_DISABLED];
    }
    ShowClientPrefMenu(param1);
  } 
  else if(action == MenuAction_End)
  {
    CloseHandle(menu);
  }
}

public Action:Command_Sound_Toggle(client, args)
{
  if(client && IsClientInGame(client))
  {
    g_clientprefs[client][SAYSOUND_PREF_DISABLED]  = ! g_clientprefs[client][SAYSOUND_PREF_DISABLED];
    SetClientCanHearSaysounds(client, !g_clientprefs[client][SAYSOUND_PREF_DISABLED]);
  }

  return Plugin_Handled;
}

public Action:Command_Sound_Menu(client, args)
{
  if(client && IsClientInGame(client))
  {
    if(g_access[client] == SAYSOUND_ADMIN)
    {
      DisplayMenu(gh_adminmenu, client, 60);
    }
    else
    {
      DisplayMenu(gh_menu, client, 60);
    }
  }

  return Plugin_Handled;
}

public menu_handler(Handle:menu,MenuAction:action,client,selection)
{
  if(action==MenuAction_Select)
  {
    decl String:SelectionInfo[SAYSOUND_TRIGGER_SIZE];
    if (GetMenuItem(menu,selection,SelectionInfo,sizeof(SelectionInfo)))
    {
      if(gb_enabled && !g_clientprefs[client][SAYSOUND_PREF_DISABLED] && !g_clientprefs[client][SAYSOUND_PREF_BANNED])		// enabled, they can emit sounds to others
      {
        AttemptSaySound(client, SelectionInfo);
      }
    }
  }
}

public OnAdminMenuReady(Handle:topmenu)
{
  if (topmenu != hAdminMenu)
  {
    hAdminMenu = topmenu;
    new TopMenuObject:server_commands = FindTopMenuCategory(hAdminMenu, ADMINMENU_SERVERCOMMANDS);
    AddToTopMenu(hAdminMenu, "sm_soundlist", TopMenuObject_Item, Play_Admin_Sound, server_commands, "sm_soundlist", ADMFLAG_GENERIC);
  }
}

public Play_Admin_Sound(Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, param, String:buffer[], maxlength)
{
  if (action == TopMenuAction_DisplayOption)
  {
    Format(buffer, maxlength, "Play A Saysound");
  }
  else if (action == TopMenuAction_SelectOption)
  {
    Command_Sound_Menu(param, 0);
  }
}

