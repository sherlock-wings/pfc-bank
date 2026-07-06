# !/bin/bash/
cd $HOMEDIR/pfc-bank/dbt_code
uv run dbt build 
cd .. && cd dashboard
npm run sources && npm run dev
