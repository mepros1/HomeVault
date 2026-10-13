package com.homevault.server.quota;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/** Global daily analysis budget (cost fuse); see V2 migration. */
@Repository
public class BudgetRepository {

  private final JdbcClient jdbc;

  public BudgetRepository(JdbcClient jdbc) {
    this.jdbc = jdbc;
  }

  /** True when one analysis fits in today's budget (and is now counted). */
  public boolean consume(int dailyLimit) {
    Integer count =
        jdbc.sql("select consume_daily_budget(:limit)").param("limit", dailyLimit).query(Integer.class).single();
    return count != null && count >= 0;
  }

  public void release() {
    jdbc.sql("select release_daily_budget()").query().listOfRows();
  }
}
