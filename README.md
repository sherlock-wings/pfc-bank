# TL;DR 

Get a mobile-friendly, AI-ready, 360-degree view of your personal finances and budget, for cheap.

![Project Data Flow](img/lightwt-family-finance-analytics.png)

# The Details

What if you could get all the benefits of a highly customized data pipeline and a analytics dashboard applied to your Finances, with minimal setup? This project attempts to answer how you might do that. The idea is to have no persisted footprint-- your data lives only as files, not in a persisted database. 

By using SimpleFIN, we can pull aggregated bank data produced by Navy Federal via MX, an affiliate firm that provides a secure source of financial records. SimpleFIN allows us to use python to extract those records, which then get stored in S3 in their raw form. Then, using DuckDB as a query engine, we spin up a dbt project to consolidate, clean, and serve that data in an output reporting layer. That layer can then be visualized with free dashboarding tools like evidence.dev, which offers a brilliant Business-Intelligence as Code solution. This platform is mobile-first and AI compatible, so it can easily deliver insights to humans and AI agents alike.

This allows the every day individual or small family to get deep CPA-level insights onto their own personal finance for no more than the cost of a SimpleFIN subscription ($15/year at time of last edit.)