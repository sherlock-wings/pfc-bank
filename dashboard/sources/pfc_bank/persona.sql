-- Persona display fields (family name + home address) for the dashboard.
-- These are labels, not transactional data, so they arrive as EVIDENCE_VAR__*
-- env vars (like ${data_root}) rather than from S3. persona.sh writes them into
-- dashboard/.env.local from the persona's identity; dashboard/.env holds the
-- committed defaults.
select '${family_name}' as family_name,
       '${home_address}' as home_address
