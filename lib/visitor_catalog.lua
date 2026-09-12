-- Contexts and move IDs select the model's authored animation dispatch, never
-- guessed clip indices. Missing dispatch entries safely return to idle.
local C={
 caterpie={10,4.5,'perch','idle'},weedle={13,4,'ground','idle'},
 oddish={43,5,'ground','sleep'},paras={46,5,'ground',10},
 pikachu={25,6,'ground',39},eevee={133,6,'ground',39},
 jigglypuff={39,6,'ground',47},butterfree={12,7,'fly',77},
 pidgey={16,5,'fly','idle'},pidgeotto={17,8,'fly','idle'},
 meowth={52,7,'ground',6},persian={53,9,'ground','sleep'},
 rattata={19,4,'ground',39},snubbull={209,6,'ground',39},
 growlithe={58,7,'ground',46},abra={63,6,'hover','sleep'},
 zubat={41,6,'fly','idle'},golbat={42,9,'fly','idle'},
 geodude={74,6,'hover',111},clefairy={35,6,'ground',47},
 misdreavus={200,7,'hover','idle'},gastly={92,8,'hover','idle'},
 yanma={193,6,'fly','idle'},ledyba={165,6,'fly','idle'},
 hooh={250,16,'high','idle'},mew={151,5,'hover','entrance'},
}
C.pools={grass={'pidgey','butterfree','oddish','paras','pikachu','eevee','jigglypuff','weedle','ledyba'},
 town={'meowth','rattata','growlithe','eevee','snubbull','persian','abra','pidgey'},
 cave={'zubat','geodude','clefairy','golbat','gastly','misdreavus'},
 freshwater={'yanma','butterfree','pidgey','ledyba','pidgeotto'}}
return C
