--[[
	SCPTips (ModuleScript) — à placer dans ReplicatedStorage.

	Répliques de D-0451 « Le Fou », le Classe D enfermé dans le hall de transit (voir CrazyDClass).

	RÈGLE : le hall de transit ne cite AUCUNE anomalie. Ni numéro, ni nom, ni surnom.
	Les SCP n'existent qu'une fois la partie lancée. Le Fou parle donc par allusions décousues :
	le joueur qui a vécu la partie comprend, celui qui arrive ne comprend rien (et c'est voulu).

	Les clés de ENTRIES sont des identifiants internes (dossier SCPCodex), jamais affichés.
	  - greet       : première réplique quand il « reconnaît » ce que le joueur a vu ;
	  - greetDeaths : idem si le joueur est mort au moins 2 fois (%d = nombre de morts) ;
	  - tips        : conseils déguisés, un par conversation, dans l'ordre, puis en boucle.
	Les conseils doivent rester vrais par rapport aux mécaniques du jeu.
]]

local SCPTips = {}

SCPTips.SPEAKER = "D-0451"

-- Ordre de priorité des anomalies (identifiants internes du dossier)
SCPTips.ORDER = { "SCP-173", "SCP-096", "SCP-106", "SCP-049", "SCP-939" }

SCPTips.ENTRIES = {
	["SCP-173"] = {
		greet = {
			"Tu l'as vue. Hein. Tu l'as vue. Tes yeux sont tout secs, tout rouges... comme les miens.",
			"Le bruit. Le bruit de pierre qui frotte. Tu l'entends quand tu dors ? Moi je dors plus.",
			"Elle était déjà là quand t'as ouvert les yeux. Elle est toujours déjà là.",
		},
		greetDeaths = {
			"%d fois. %d fois ta nuque a fait crac. Moi je compte. Je compte tout.",
		},
		tips = {
			"Faut la regarder. Toujours. Quelqu'un doit TOUJOURS la regarder. Même pendant que tu me parles. Surtout.",
			"Tes yeux se ferment tout seuls. Tout seuls ! Mais tu peux choisir quand. La touche B. B comme... B.",
			"À deux, jamais en même temps. Toi tu fermes, l'autre ouvre. Toi tu fermes, l'autre ouvre. Toi tu...",
			"Un mur entre elle et toi, ça compte pas. Elle aime les murs. Elle attend derrière.",
			"Lui tourne jamais le dos. Recule. Recule en la regardant. Doucement. Doucement.",
			"Trop près, c'est fini. Même si tu regardes. Garde de la place entre vous.",
		},
	},
	["SCP-096"] = {
		greet = {
			"Il pleurait, hein ? Il pleure tout le temps. Moi aussi je pleurais, avant.",
		},
		greetDeaths = {
			"%d fois. Tu l'as regardé %d fois. T'apprends pas, toi.",
		},
		tips = {
			"Son visage. Faut pas. Même un bout. Même de loin. Regarde tes chaussures, elles sont bien, tes chaussures.",
			"Baisse les yeux et longe les murs. Les murs, ils te regardent pas, eux.",
			"S'il crie, c'est trop tard. Les portes servent à rien. Rien sert à rien.",
		},
	},
	["SCP-106"] = {
		greet = {
			"Ça sent la rouille sur toi. La rouille et la cave. Il t'a touché, hein ?",
		},
		greetDeaths = {
			"%d fois en bas, dans le noir. Moi j'y suis allé une fois. Une partie de moi y est encore.",
		},
		tips = {
			"Le noir qui coule par terre... marche pas dedans. Jamais.",
			"Il aime pas la lumière. Reste là où c'est éclairé. Comme ici. Ici c'est bien éclairé. Trop.",
			"Il y a une machine, quelque part. Un os qui casse. Ça le fait rentrer chez lui. Il faut appuyer.",
		},
	},
	["SCP-049"] = {
		greet = {
			"Il t'a dit que t'étais malade ? Il a raison. On l'est tous. Toi, moi, les néons.",
		},
		greetDeaths = {
			"%d fois guéri. Félicitations. T'as jamais été aussi en forme.",
		},
		tips = {
			"Il court pas. Jamais. Toi, si. Cours.",
			"Ferme les portes derrière toi. Lui, il les ouvre doucement. Très doucement.",
			"Le laisse pas s'approcher pour te parler. Il parle bien. Trop bien.",
		},
	},
	["SCP-939"] = {
		greet = {
			"Elles t'ont appelé avec ta voix ? Avec TA voix ? Moi elles m'appellent encore, la nuit.",
		},
		greetDeaths = {
			"%d fois. T'as répondu, hein. Faut pas répondre.",
		},
		tips = {
			"Elles voient rien. Elles écoutent. Accroupis-toi. Marche comme une souris.",
			"Cours pas. Tes pas, c'est une cloche pour le dîner.",
			"Parle pas. Elles copient. Elles copient tout. Même toi.",
		},
	},
}

-- Le joueur n'a encore rien vécu : il délire
SCPTips.NOTHING = {
	{
		"Chhht. Tu entends ? Les néons. Ils comptent. Un, deux, trois... non. Non non non.",
		"Toi t'as encore les yeux tout propres. Ça durera pas. Reviens me voir après. SI tu reviens.",
	},
	{
		"Ils m'ont donné un numéro. J'avais un nom, avant. Il était joli. Je l'ai rangé quelque part.",
		"Passe les portes, là-bas. Et après, viens me raconter. Moi je raconterai le reste.",
	},
	{
		"Le béton... ça sent le béton mouillé, ici. Comme en bas. Pourquoi ça sent comme en bas ?",
		"Tu sais rien. C'est bien. C'est mieux. Profite. Hé. Hé hé.",
	},
	{
		"La caméra me regarde. Je la regarde aussi. Comme ça, personne bouge. C'est la règle.",
		"Tu comprendras. Tout le monde finit par comprendre. Les autres sont pas revenus le dire.",
	},
}

-- Tous les conseils ont déjà été donnés : il recommence, en le disant
SCPTips.REPEAT = {
	"Je l'ai déjà dit. Je le redis. Je le redis tout le temps :",
	"Encore ? Encore. Écoute, cette fois :",
}

-- Dernière réplique
SCPTips.BYE = {
	"Va-t'en. Et ferme pas les yeux en partant.",
	"Chut. Ils écoutent. Va.",
	"Reviens. Ou reviens pas. La plupart reviennent pas.",
	"Les néons ont recommencé à compter. Va-t'en avant qu'ils arrivent à toi.",
}

return SCPTips
