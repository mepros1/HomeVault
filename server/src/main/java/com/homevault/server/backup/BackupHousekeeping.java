package com.homevault.server.backup;

import com.homevault.server.config.HomeVaultProperties;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/** Applies the privacy policy's retention: backups of devices unseen for a year go away. */
@Component
public class BackupHousekeeping {

  private static final Logger log = LoggerFactory.getLogger(BackupHousekeeping.class);

  private final BackupRepository backups;
  private final HomeVaultProperties props;

  public BackupHousekeeping(BackupRepository backups, HomeVaultProperties props) {
    this.backups = backups;
    this.props = props;
  }

  @Scheduled(fixedDelayString = "PT24H", initialDelayString = "PT5M")
  public void purgeInactive() {
    int removed = backups.purgeInactive(props.backup().retention());
    if (removed > 0) log.info("report_backups purge removed={}", removed);
  }
}
