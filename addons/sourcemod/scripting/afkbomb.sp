#pragma semicolon 1
#pragma newdecls required

#include <sdktools_functions>
#include <sdktools_entinput>
#include <cstrike>
#include <colors_ws>

ConVar
	cvAfkBombMsg,
	cvAfkBombAction,
	cvAfkBombFreeze,
	cvAfkBombCheckAction,
	cvAfkBombDelay,
	cvAfkBomb,
	cvAfkBombNumber;

static int g_roundNumber;

int
	g_bombId,
	g_bombMoney,
	g_bombArmor,
	g_bombGuns[4],
	g_bombButtons,
	g_iAccount,
	g_iVelocityOffset,
	g_lateCheckCount,
	game[4] = {0,1,2,3},
	Engine_Version;		//0-UNDEFINED|1-css34|2-css|3-csgo

float
	fBombEye[3],
	fBombAngle[3],
	fBombOrigin[3],
	fBombVelocity[3];

bool
	bShouldMsgBombDrop,
	bFirstBombDrop;

char
	sFile[512];

int GetCSGame()
{
	if (GetFeatureStatus(FeatureType_Native, "GetEngineVersion") == FeatureStatus_Available) 
	{
		switch (GetEngineVersion())
		{
			case Engine_SourceSDK2006: return game[1];
			case Engine_CSS: return game[2];
			case Engine_CSGO: return game[3];
		}
	}
	return game[0];
}

public APLRes AskPluginLoad2()
{
	Engine_Version = GetCSGame();
	switch(Engine_Version)
	{
		case 0: SetFailState("Game is not supported!");
		case 1: LoadTranslations("afkbomb_cssv34.phrases");
		case 2: LoadTranslations("afkbomb_css.phrases");
		case 3: LoadTranslations("afkbomb_csgo.phrases");
	}

	return APLRes_Success;
}

public Plugin myinfo =
{
	name = "Afk Bomb",
	author = "RedSword/Bob Le Ponge (rewritten by Nek.'a 2x2 | ggwp.site)",
	description = "Сбросить бомбу, если игрок АФК",
	version = "1.5.3",
	url = "http://www.sourcemod.net/"
};

public void OnPluginStart()
{
	cvAfkBombMsg = CreateConVar("sm_afkbomb_msg", "1", "Сообщить когда бомба сброшена - 1, когда бомба передана случайному Т - 0", _, true, _, true, 1.0);
	
	cvAfkBombAction = CreateConVar("sm_afkbomb_action", "0", "Если афк в начале раунда, то 1 - выкинуть бомбу, 0 - выдать рандомному Т", _, true, _, true, 1.0);
	
	cvAfkBombFreeze = CreateConVar("sm_afkbomb_freezetime", "0", "Если установлено \"mp_freezetime N\" то добавлять ли это значение", _, true, _, true, 1.0);
	
	cvAfkBombCheckAction = CreateConVar("sm_afkbomb_latecheckaction", "1", "Когда АФК в начале раунда: Выкнуть бомбу - 1, отдать случайному Т - 0 (не рекомендуется)", _, true, _, true, 1.0);
	
	cvAfkBombDelay = CreateConVar("sm_afkbomb_delay", "5.0", "Время между двумя проверками, чтобы сбросить бомбу (секунд)", _, true);

	cvAfkBomb = CreateConVar("sm_afkbomb", "2", "Сколько должно пройти времени прежде чем афк скинет бомбу 0- выкл., 1+ - вкл.", FCVAR_NOTIFY, true, 0.0);

	cvAfkBombNumber = CreateConVar("sm_afkbomb_number", "2", "Количество проверок, которые нужно сделать перед сбросом бомбы", FCVAR_NOTIFY, true, 0.0);

	HookEvent("round_start", Event_RoundStart);
	
	//Prevent re-running a function Предотвращение повторного запуска функции
	g_iAccount = FindSendPropInfo("CCSPlayer", "m_iAccount");
	g_iVelocityOffset = FindSendPropInfo("CBasePlayer", "m_vecVelocity[0]");
	
	AutoExecConfig(true, "afk_bomb");

	BuildPath(Path_SM, sFile, sizeof(sFile), "logs/AfkBomb.log");
}

void Event_RoundStart(Handle event, const char[] name, bool dontBroadcast)
{
	if(!cvAfkBomb.IntValue)
		return;

	++g_roundNumber;
	bFirstBombDrop = true;
	CreateTimer(1.0, CheckForBomber, g_roundNumber, TIMER_FLAG_NO_MAPCHANGE);
	return;
}

Action CheckForBomber(Handle timer, any roundNumber)
{
	if(roundNumber != g_roundNumber)
		return Plugin_Continue;
	
	//If we're to look for the bomber, that means he's not found yet and that he won't repeat his speech
	bShouldMsgBombDrop = true;
	g_lateCheckCount = 0;
	
	for(int i = MaxClients; i >= 1; --i) if(IsClientInGame(i) && IsPlayerAlive(i) && GetPlayerWeaponSlot(i, 4) != -1)
	{
		FirstScan(i);
		return Plugin_Continue;
	}

	//We rerun the function if not found
	if(cvAfkBombNumber.IntValue)
	{
		bFirstBombDrop = false;
		CreateTimer(cvAfkBombDelay.FloatValue, CheckForBomber, roundNumber, TIMER_FLAG_NO_MAPCHANGE );
	}
	return Plugin_Continue;
}

void FirstScan(int client)
{
	if(!cvAfkBomb.IntValue)
		return;

	float timeUntilScan = cvAfkBombDelay.FloatValue;
	if(bFirstBombDrop)
	{
		timeUntilScan = cvAfkBomb.FloatValue;
		if(cvAfkBombFreeze.BoolValue)
			timeUntilScan += GetConVarFloat(FindConVar("mp_freezetime"));
	}
	getState(client); //Save state (various stats in globals)

	BroadcastDataPack(client, g_roundNumber, timeUntilScan);	

	return;
}

void BroadcastDataPack(int client, int iCountRound, float timeUntilScan)
{
	if(!IsClientValid(client))
		return;
	//LogToFile(sFile, "Работает 1 [%N]", client);
	DataPack hPack = new DataPack();
	hPack.WriteCell(GetClientUserId(client));
	hPack.WriteCell(iCountRound);
	CreateTimer(timeUntilScan, Timer_SecondScanDataPack, hPack, TIMER_FLAG_NO_MAPCHANGE);
}

Action Timer_SecondScanDataPack(Handle timer, DataPack hPack)
{
	hPack.Reset();
	int client = GetClientOfUserId(hPack.ReadCell());
	int roundNumber = hPack.ReadCell();
	delete hPack;
	
	if(!IsClientValid(client))
		return Plugin_Continue;

	float lateCheckDelay = cvAfkBombDelay.FloatValue;

	if(g_roundNumber == roundNumber) //If we're in the same round
	{
		if(client != 0 && IsClientInGame(client) && IsPlayerAlive(client) && sameState(client))
		{
			if(bFirstBombDrop || ++g_lateCheckCount >= cvAfkBombNumber.IntValue)
			{
				if((bFirstBombDrop && cvAfkBombAction.BoolValue) || (!bFirstBombDrop && cvAfkBombCheckAction.BoolValue))
					CS_DropWeapon(client, GetPlayerWeaponSlot(client, 4), true, true);
				else
				{
					stripAndGive2RandomTBomb(client); //The function takes care of its own verbose
					CheckForBomber(INVALID_HANDLE, roundNumber); //lets start next check right now
					return Plugin_Continue; //no latecheck problem are possible so 
				}
				//End 1.5 changes 
				lateCheckDelay = 1.5;
				
				if(bShouldMsgBombDrop) //Do not repeat !
				{
					if(cvAfkBombMsg.BoolValue)
						FakeClientCommand(client, "say_team %t", "Drop Bomb");
					bShouldMsgBombDrop = false;
				}
			}
			BroadcastDataPack(client, g_roundNumber, lateCheckDelay);	
		}
		else if(cvAfkBombNumber.IntValue)	//if bomber is lost, find him again (if we want to lateCheck)
		{
			bFirstBombDrop = false;
			CreateTimer(lateCheckDelay, CheckForBomber, roundNumber, TIMER_FLAG_NO_MAPCHANGE);
		}
	}
	return Plugin_Continue;
}

bool stripAndGive2RandomTBomb(int client) //Since 1.4.0 (Change 2/2) ; changed in 1.5 (priorize moving players)
{
	int[] terrorists = new int[MaxClients];
	int[] movTerrorists = new int[MaxClients];
	int sizeT, sizeMovT;
	float velocX; //no real need for Y & Z
	
	for(int i = 1; i <= MaxClients; ++i) if(IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i) && i != client)
	{
		terrorists[sizeT++] = i;
		velocX = GetEntDataFloat(i, g_iVelocityOffset);
		if(velocX != 0.0) movTerrorists[ sizeMovT++ ] = i;
	}
	if(!sizeT)
		return false;

	char sClassName[MAX_NAME_LENGTH];  
	
	int iEntIndex = GetPlayerWeaponSlot(client, 4);
	
	GetEdictClassname(iEntIndex, sClassName, sizeof(sClassName));  
	if(StrEqual(sClassName, "weapon_c4", false))  
	{
		RemovePlayerItem(client, iEntIndex ); 
		AcceptEntityInput( iEntIndex, "kill" );
	}
	if(sizeMovT > 0) //priorize moving players
		GivePlayerItem( movTerrorists[ GetRandomInt( 0, sizeMovT - 1 ) ], "weapon_c4" );
	else
		GivePlayerItem( terrorists[ GetRandomInt( 0, sizeT - 1 ) ], "weapon_c4" );

	if(cvAfkBombMsg.BoolValue)
	{
		for(int i = 1; i <= MaxClients; i++) if(IsClientValid(i) && !IsFakeClient(i))
			CPrint(i, "Tag", "%t", "Tag", "StripNGive Bomb", client);
	}
	return true;
}

Action getState(any client, bool lateCheck=false)
{	
	g_bombId = client;
	if(!lateCheck)
	{
		g_bombMoney = GetEntData(client, g_iAccount);	//Money
		g_bombArmor = GetClientArmor(client);	//Armor
		g_bombButtons = GetClientButtons(client);	//Buttons pressed
	}
	//Guns
	for(int i = 3; i >= 0; --i)
		g_bombGuns[ i ] = GetPlayerWeaponSlot( client, i + 1 );
	//Vectors
	GetClientEyeAngles( client, fBombEye );
	GetClientAbsAngles( client, fBombAngle );
	GetClientAbsOrigin( client, fBombOrigin );
	GetEntPropVector( client, Prop_Data, "m_vecVelocity", fBombVelocity );
	return Plugin_Continue;
}

//Compare current state from those in the global vars
bool sameState(any client, bool lateCheck=false )
{
	if(g_bombId != client)
		return false;

	if(!lateCheck)
	{
		if(g_bombMoney != GetEntData(client, g_iAccount)) return false;	//Money
		if(g_bombArmor != GetClientArmor(client)) return false;			//Armor
		if(g_bombButtons != GetClientButtons(client)) return false;		//Buttons pressed
	}
	
	//Guns
	for(int i = 3; i >= 0; --i) if(g_bombGuns[i] != GetPlayerWeaponSlot(client, i + 1)) return false;

	//Vectors
	float eyeVec[3], absAngVec[3], absOriVec[3], absVloVec[3];
	GetClientEyeAngles(client, eyeVec);
	GetClientAbsAngles(client, absAngVec);
	GetClientAbsOrigin(client, absOriVec);
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", absVloVec);

	for(int i = 0; i < 3; i++)
	{
		if(eyeVec[i] != fBombEye[i] || absAngVec[i] != fBombAngle[i] || absOriVec[i] != fBombOrigin[i] || absVloVec[i] != fBombVelocity[i])
			return false;
	}
	return true;
}

bool IsClientValid(int client)
{
	return 0 < client <= MaxClients && IsClientInGame(client);
}