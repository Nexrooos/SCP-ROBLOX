--[[
	SCPTips (ModuleScript) — à placer dans ReplicatedStorage.

	Répliques de D-0451 « Le Fou », le Classe D enfermé dans le hall de transit (voir CrazyDClass).
	Il ne parle que des anomalies que le joueur a déjà rencontrées (dossier SCPCodex) :
	  - greet       : première réplique quand on lui parle de cette anomalie ;
	  - greetDeaths : idem si le joueur est mort au moins 2 fois contre elle (%d = nombre de morts) ;
	  - tips        : conseils, donnés un par conversation, dans l'ordre, puis en boucle.

	Pour ajouter une anomalie : une entrée ici + un appel à SCPCodex.markSeen(player, "SCP-XXX")
	là où le joueur la rencontre ou meurt.
	Les conseils doivent rester vrais par rapport aux mécaniques du jeu.
]]

local SCPTips = {}

SCPTips.SPEAKER = "D-0451 « LE FOU »"

-- Ordre d'affichage (et de priorité) des anomalies
SCPTips.ORDER = { "SCP-173", "SCP-096", "SCP-106", "SCP-049", "SCP-939" }

SCPTips.ENTRIES = {
	["SCP-173"] = {
		name = "la statue",
		greet = {
			"La statue... T'as vu la statue. Je le vois. T'as les yeux tout secs.",
			"Crrrr... crrrr... Tu l'entends aussi, le bruit de pierre ? Non ? Moi si. Tout le temps.",
			"Elle t'a regardé, hein ? Non. C'est TOI qui as arrêté de la regarder. Grosse erreur.",
		},
		greetDeaths = {
			"%d fois. T'es mort %d fois contre la statue. Moi zéro. Parce que moi je cligne PAS.",
		},
		tips = {
			"Elle bouge QUE quand personne la regarde. Personne. Faut toujours quelqu'un qui la fixe. Toujours.",
			"Tes yeux vont se fermer tout seuls, t'y peux rien. Mais la touche B, elle, te fait cligner quand TOI t'as décidé. Pas quand ELLE a décidé.",
			"À plusieurs, vous clignez JAMAIS en même temps. Un cligne, l'autre regarde. Chacun son tour, comme à la cantine.",
			"Un mur entre elle et toi, ça compte pas comme regarder. Elle le sait. Elle attend que tu passes derrière.",
			"Elle est plus rapide que toi. Beaucoup plus. Lui tourne jamais le dos : recule en la regardant.",
			"Si elle te touche, crac. Pas de deuxième chance. Garde tes distances, même quand tu la regardes.",
		},
	},
	["SCP-096"] = {
		name = "le timide",
		greet = {
			"Le grand pâle qui pleure... T'as vu son visage ? Si t'es là, c'est que non. Ou pas longtemps.",
		},
		greetDeaths = {
			"%d fois il t'a eu ? Tu regardes trop. Les gens regardent toujours trop.",
		},
		tips = {
			"Son visage. Faut JAMAIS voir son visage. Même un petit bout. Même sur une photo.",
			"Baisse les yeux. Longe les murs. Regarde tes pieds, ils sont très bien, tes pieds.",
			"Une fois qu'il t'a vu le regarder, aucun mur l'arrête. Aucun. Cours pas, prie.",
		},
	},
	["SCP-106"] = {
		name = "le vieux",
		greet = {
			"Le vieux... il sent la rouille. Il passe à travers les murs comme toi tu passes une porte.",
		},
		greetDeaths = {
			"%d fois dans sa petite pièce noire. Moi j'y suis allé une fois. J'en suis jamais vraiment revenu.",
		},
		tips = {
			"Le noir qui coule par terre, c'est lui. Marche pas dedans.",
			"Il aime pas la lumière. Reste dans les coins éclairés.",
			"Il y a une salle avec une machine... un os qui craque. Ça le fait revenir dans sa cage. Faut juste quelqu'un pour appuyer.",
		},
	},
	["SCP-049"] = {
		name = "le docteur",
		greet = {
			"Le docteur ! Il est poli, hein ? Il dit que t'es malade. Il ment pas. On est tous malades.",
		},
		greetDeaths = {
			"%d fois soigné. Félicitations. T'es en pleine forme maintenant. Hé hé.",
		},
		tips = {
			"Il court pas. Jamais. Toi, tu peux.",
			"Ferme les portes derrière toi. Lui, il les ouvre lentement. Très lentement.",
			"Un seul contact et c'est fini. Laisse-le pas s'approcher pour te parler.",
		},
	},
	["SCP-939"] = {
		name = "les voix",
		greet = {
			"Les voix dans le noir... Elles t'ont appelé par ton nom ? C'était pas tes amis.",
		},
		greetDeaths = {
			"%d fois. T'as répondu quand elles t'ont appelé, hein ? Faut pas répondre.",
		},
		tips = {
			"Elles voient rien. Elles ENTENDENT. Accroupis-toi, marche doucement.",
			"Cours pas. Le bruit de tes pas, c'est une cloche pour le dîner.",
			"Parle pas dans le micro. Elles copient les voix. Elles copient LA TIENNE.",
		},
	},
}

-- Le joueur n'a encore rien rencontré
SCPTips.NOTHING = {
	{
		"Toi t'as encore rien vu. Ça se voit : t'as encore toutes tes vertèbres.",
		"Reviens quand t'auras croisé quelque chose là-dedans. SI tu reviens. Hé. Hé hé.",
	},
	{
		"Moi j'ai TOUT vu. Ils me gardent ici parce que j'oublie rien.",
		"Va faire un tour derrière les sas. Après, on pourra parler, toi et moi.",
	},
	{
		"Chut. Ils écoutent. ...Non, toi tu sais rien encore, tu sers à rien.",
		"Rapporte-moi une histoire. Une vraie. Avec quelque chose qui bouge pas quand on le regarde.",
	},
}

-- Tous les conseils d'une anomalie ont déjà été donnés : il recommence, en le disant
SCPTips.REPEAT = {
	"Je te l'ai déjà dit, mais tu écoutes jamais :",
	"Encore ? Bon. Je répète, pour ta nuque :",
}

-- Dernière réplique
SCPTips.BYE = {
	"Va-t'en maintenant. Et ferme pas les yeux en partant.",
	"Reviens me voir. Ou pas. La plupart reviennent pas.",
	"Chut. Ils écoutent. Va.",
	"Dis bonjour à la statue de ma part. Non. Dis-lui rien.",
}

return SCPTips
