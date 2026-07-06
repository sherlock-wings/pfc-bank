# !/bin/bash/
# chaining like this makes the whole thing fail if one bit fails
# which i think is what i want, so keeping like this for now
cd $HOMEDIR/pfc-bank/dbt_code && uv run dbt build && cd .. && cd dashboard &&npm run sources && npm run dev
