-- =====================================================================
-- scheme.sql  |  Web Perpustakaan & Bebas Pustaka
-- DBMS    : MySQL 8.4 (Laragon) -- butuh MySQL >= 8.0.16
-- Cara    : HeidiSQL -> buka file ini -> tekan F9 (jalankan SEMUA, jangan hanya blok terpilih)
-- Catatan : script ini membuat database baru bernama `perpus`.
--           JANGAN jalankan di database `mysql` (itu database sistem).
-- AWAS    : baris DROP DATABASE di bawah MENGHAPUS database `perpus` beserta datanya kalau file ini dijalankan ulang.
--           Hapus/komentari baris itu setelah database terisi data asli.
-- =====================================================================

DROP DATABASE IF EXISTS perpus;
CREATE DATABASE perpus CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE perpus;

SET FOREIGN_KEY_CHECKS = 0;

-- ---------------------------------------------------------------------
-- 1. MASTER: FAKULTAS & PRODI
-- ---------------------------------------------------------------------
CREATE TABLE faculties (
  id          SMALLINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  code        VARCHAR(10)  NOT NULL UNIQUE,
  name        VARCHAR(150) NOT NULL,
  created_at  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE study_programs (
  id          SMALLINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  faculty_id  SMALLINT UNSIGNED NOT NULL,
  code        VARCHAR(10)  NOT NULL UNIQUE,
  name        VARCHAR(150) NOT NULL,
  degree      VARCHAR(10)  NOT NULL DEFAULT 'S1',
  created_at  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_prodi_faculty FOREIGN KEY (faculty_id) REFERENCES faculties(id) ON DELETE RESTRICT,
  INDEX idx_study_programs_faculty (faculty_id)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 2. USER & ANGGOTA
-- ---------------------------------------------------------------------
CREATE TABLE users (
  id             CHAR(36) NOT NULL DEFAULT (UUID()) PRIMARY KEY,
  email          VARCHAR(190) NOT NULL UNIQUE,              -- collation _ci: tidak peka huruf besar/kecil
  password_hash  VARCHAR(255) NOT NULL,
  full_name      VARCHAR(150) NOT NULL,
  role           ENUM('mahasiswa','pustakawan','admin') NOT NULL DEFAULT 'mahasiswa',
  phone          VARCHAR(20),
  is_active      TINYINT(1)   NOT NULL DEFAULT 1,
  last_login_at  DATETIME,
  created_at     TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at     TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE members (
  id                CHAR(36) NOT NULL DEFAULT (UUID()) PRIMARY KEY,
  user_id           CHAR(36)     NOT NULL UNIQUE,
  member_code       VARCHAR(30)  NOT NULL UNIQUE,           -- barcode kartu anggota
  nim               VARCHAR(30)  NOT NULL UNIQUE,
  study_program_id  SMALLINT UNSIGNED NOT NULL,
  entry_year        SMALLINT     NOT NULL,
  status            ENUM('aktif','nonaktif','diblokir','alumni') NOT NULL DEFAULT 'aktif',
  max_loans         SMALLINT     NOT NULL DEFAULT 3,
  registered_at     DATE         NOT NULL DEFAULT (CURRENT_DATE),
  expired_at        DATE,
  deactivated_at    DATETIME,                               -- diisi saat bebas pustaka terbit
  created_at        TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at        TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_members_user  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  CONSTRAINT fk_members_prodi FOREIGN KEY (study_program_id) REFERENCES study_programs(id),
  CONSTRAINT ck_members_year  CHECK (entry_year BETWEEN 1990 AND 2100),
  CONSTRAINT ck_members_max   CHECK (max_loans >= 0),
  INDEX idx_members_prodi (study_program_id),
  INDEX idx_members_status (status)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 3. KOLEKSI
-- ---------------------------------------------------------------------
CREATE TABLE categories (
  id        SMALLINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  name      VARCHAR(100) NOT NULL UNIQUE,
  ddc_code  VARCHAR(20)
) ENGINE=InnoDB;

CREATE TABLE books (
  id            CHAR(36) NOT NULL DEFAULT (UUID()) PRIMARY KEY,
  isbn          VARCHAR(20) UNIQUE,
  title         VARCHAR(300) NOT NULL,
  authors       TEXT         NOT NULL,
  publisher     VARCHAR(150),
  publish_year  SMALLINT,
  edition       VARCHAR(50),
  language      VARCHAR(30)  DEFAULT 'Indonesia',
  category_id   SMALLINT UNSIGNED,
  call_number   VARCHAR(50),
  description   TEXT,
  cover_url     TEXT,
  created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_books_category FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE SET NULL,
  CONSTRAINT ck_books_year CHECK (publish_year IS NULL OR publish_year BETWEEN 1400 AND 2100),
  INDEX idx_books_category (category_id),
  FULLTEXT INDEX ft_books_search (title, authors)           -- pakai MATCH(title, authors) AGAINST('kata' IN NATURAL LANGUAGE MODE)
) ENGINE=InnoDB;

CREATE TABLE book_items (
  id           CHAR(36) NOT NULL DEFAULT (UUID()) PRIMARY KEY,
  book_id      CHAR(36)    NOT NULL,
  barcode      VARCHAR(40) NOT NULL UNIQUE,
  status       ENUM('tersedia','dipinjam','dipesan','rusak','hilang','dihapus') NOT NULL DEFAULT 'tersedia',
  cond         ENUM('baik','cukup','rusak_ringan','rusak_berat') NOT NULL DEFAULT 'baik',  -- "condition" reserved word di MySQL
  location     VARCHAR(80),
  price        DECIMAL(12,2) NOT NULL DEFAULT 0,
  acquired_at  DATE,
  created_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_items_book FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE CASCADE,
  CONSTRAINT ck_items_price CHECK (price >= 0),
  INDEX idx_book_items_book (book_id),
  INDEX idx_book_items_status (status)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 4. PENGATURAN (aturan pinjam, denda, syarat bebas pustaka)
-- ---------------------------------------------------------------------
CREATE TABLE settings (
  setting_key    VARCHAR(60) PRIMARY KEY,                   -- "key" reserved word di MySQL
  setting_value  VARCHAR(255) NOT NULL,
  description    TEXT,
  updated_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;

INSERT INTO settings (setting_key, setting_value, description) VALUES
  ('loan_days',                '7',    'Lama pinjam default (hari)'),
  ('max_renewals',             '2',    'Maksimal perpanjangan per peminjaman'),
  ('fine_per_day',             '1000', 'Denda keterlambatan per hari per buku (Rp)'),
  ('fine_max_multiplier',      '1',    'Batas denda terlambat = harga buku x nilai ini'),
  ('lost_fine_multiplier',     '2',    'Denda buku hilang = harga buku x nilai ini'),
  ('reservation_hold_days',    '2',    'Lama buku pesanan ditahan (hari)'),
  ('clearance_require_thesis', 'true', 'Bebas pustaka wajib unggah karya akhir ke repositori'),
  ('clearance_letter_prefix',  'BP',   'Prefix nomor surat bebas pustaka'),
  ('clearance_validity_days',  '180',  'Masa berlaku surat bebas pustaka (hari)');

-- ---------------------------------------------------------------------
-- 5. SIRKULASI
-- ---------------------------------------------------------------------
CREATE TABLE loans (
  id           CHAR(36) NOT NULL DEFAULT (UUID()) PRIMARY KEY,
  member_id    CHAR(36)  NOT NULL,
  item_id      CHAR(36)  NOT NULL,
  loaned_by    CHAR(36),
  returned_to  CHAR(36),
  loan_date    DATE      NOT NULL DEFAULT (CURRENT_DATE),
  due_date     DATE      NOT NULL,
  return_date  DATE,
  renew_count  SMALLINT  NOT NULL DEFAULT 0,
  status       ENUM('dipinjam','dikembalikan','hilang') NOT NULL DEFAULT 'dipinjam',
  notes        TEXT,
  created_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  -- trik pengganti "partial unique index": 1 eksemplar hanya boleh punya 1 peminjaman aktif
  active_item_id CHAR(36) AS (IF(status = 'dipinjam', item_id, NULL)) VIRTUAL,
  CONSTRAINT fk_loans_member   FOREIGN KEY (member_id)   REFERENCES members(id)    ON DELETE RESTRICT,
  CONSTRAINT fk_loans_item     FOREIGN KEY (item_id)     REFERENCES book_items(id) ON DELETE RESTRICT,
  CONSTRAINT fk_loans_loanedby FOREIGN KEY (loaned_by)   REFERENCES users(id),
  CONSTRAINT fk_loans_retto    FOREIGN KEY (returned_to) REFERENCES users(id),
  CONSTRAINT ck_loans_due   CHECK (due_date >= loan_date),
  CONSTRAINT ck_loans_ret   CHECK (return_date IS NULL OR return_date >= loan_date),
  CONSTRAINT ck_loans_renew CHECK (renew_count >= 0),
  UNIQUE INDEX uq_loans_item_active (active_item_id),
  INDEX idx_loans_member (member_id),
  INDEX idx_loans_item (item_id),
  INDEX idx_loans_status (status),
  INDEX idx_loans_due (due_date)
) ENGINE=InnoDB;

CREATE TABLE reservations (
  id           CHAR(36) NOT NULL DEFAULT (UUID()) PRIMARY KEY,
  member_id    CHAR(36) NOT NULL,
  book_id      CHAR(36) NOT NULL,
  item_id      CHAR(36),
  status       ENUM('menunggu','siap_diambil','selesai','dibatalkan','kedaluwarsa') NOT NULL DEFAULT 'menunggu',
  reserved_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  ready_at     DATETIME,
  expires_at   DATETIME,
  updated_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  active_key   CHAR(72) AS (IF(status IN ('menunggu','siap_diambil'), CONCAT(member_id, book_id), NULL)) VIRTUAL,
  CONSTRAINT fk_res_member FOREIGN KEY (member_id) REFERENCES members(id) ON DELETE CASCADE,
  CONSTRAINT fk_res_book   FOREIGN KEY (book_id)   REFERENCES books(id)   ON DELETE CASCADE,
  CONSTRAINT fk_res_item   FOREIGN KEY (item_id)   REFERENCES book_items(id),
  UNIQUE INDEX uq_reservation_active (active_key),
  INDEX idx_reservations_member (member_id),
  INDEX idx_reservations_book (book_id, status)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 6. DENDA & PEMBAYARAN
-- ---------------------------------------------------------------------
CREATE TABLE fines (
  id             CHAR(36) NOT NULL DEFAULT (UUID()) PRIMARY KEY,
  member_id      CHAR(36)  NOT NULL,
  loan_id        CHAR(36),
  type           ENUM('terlambat','rusak','hilang','lainnya') NOT NULL,
  amount         DECIMAL(12,2) NOT NULL,
  paid_amount    DECIMAL(12,2) NOT NULL DEFAULT 0,
  status         ENUM('belum_bayar','lunas','dibebaskan') NOT NULL DEFAULT 'belum_bayar',
  reason         TEXT,
  waived_by      CHAR(36),
  waived_reason  TEXT,
  created_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_fines_member FOREIGN KEY (member_id) REFERENCES members(id) ON DELETE RESTRICT,
  CONSTRAINT fk_fines_loan   FOREIGN KEY (loan_id)   REFERENCES loans(id)   ON DELETE SET NULL,
  CONSTRAINT fk_fines_waiver FOREIGN KEY (waived_by) REFERENCES users(id),
  CONSTRAINT ck_fines_amount CHECK (amount >= 0),
  CONSTRAINT ck_fines_paid   CHECK (paid_amount >= 0 AND paid_amount <= amount),
  INDEX idx_fines_member (member_id),
  INDEX idx_fines_status (status)
) ENGINE=InnoDB;

CREATE TABLE fine_payments (
  id           CHAR(36) NOT NULL DEFAULT (UUID()) PRIMARY KEY,
  fine_id      CHAR(36)      NOT NULL,
  amount       DECIMAL(12,2) NOT NULL,
  method       ENUM('tunai','transfer','qris','lainnya') NOT NULL DEFAULT 'tunai',
  reference    VARCHAR(100),
  received_by  CHAR(36),
  paid_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_pay_fine FOREIGN KEY (fine_id)     REFERENCES fines(id) ON DELETE RESTRICT,
  CONSTRAINT fk_pay_user FOREIGN KEY (received_by) REFERENCES users(id),
  CONSTRAINT ck_pay_amount CHECK (amount > 0),
  INDEX idx_fine_payments_fine (fine_id)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 7. REPOSITORI KARYA AKHIR
-- ---------------------------------------------------------------------
CREATE TABLE thesis_submissions (
  id              CHAR(36) NOT NULL DEFAULT (UUID()) PRIMARY KEY,
  member_id       CHAR(36)     NOT NULL,
  work_type       ENUM('skripsi','tesis','disertasi','tugas_akhir','laporan_pkl','jurnal','lainnya') NOT NULL DEFAULT 'skripsi',
  title           VARCHAR(400) NOT NULL,
  abstract        TEXT,
  advisor_1       VARCHAR(150),
  advisor_2       VARCHAR(150),
  defense_year    SMALLINT,
  file_full_url   TEXT,
  file_cover_url  TEXT,
  similarity_pct  DECIMAL(5,2),
  similarity_url  TEXT,
  status          ENUM('draft','diajukan','revisi','disetujui','ditolak') NOT NULL DEFAULT 'draft',
  reviewed_by     CHAR(36),
  review_notes    TEXT,
  submitted_at    DATETIME,
  reviewed_at     DATETIME,
  created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_thesis_member   FOREIGN KEY (member_id)   REFERENCES members(id) ON DELETE CASCADE,
  CONSTRAINT fk_thesis_reviewer FOREIGN KEY (reviewed_by) REFERENCES users(id),
  CONSTRAINT ck_thesis_sim CHECK (similarity_pct IS NULL OR similarity_pct BETWEEN 0 AND 100),
  INDEX idx_thesis_member (member_id),
  INDEX idx_thesis_status (status)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 8. BEBAS PUSTAKA
-- ---------------------------------------------------------------------
-- pengganti SEQUENCE
CREATE TABLE clearance_letter_seq (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY
) ENGINE=InnoDB;

CREATE TABLE clearance_requests (
  id             CHAR(36) NOT NULL DEFAULT (UUID()) PRIMARY KEY,
  member_id      CHAR(36)    NOT NULL,
  purpose        VARCHAR(60) NOT NULL DEFAULT 'yudisium',
  thesis_id      CHAR(36),
  status         ENUM('draft','diajukan','diverifikasi','ditolak','disetujui','diterbitkan','dibatalkan') NOT NULL DEFAULT 'draft',
  chk_no_loans   TINYINT(1),
  chk_no_fines   TINYINT(1),
  chk_thesis_ok  TINYINT(1),
  verified_by    CHAR(36),
  verified_at    DATETIME,
  reject_reason  TEXT,
  submitted_at   DATETIME,
  created_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  -- 1 anggota hanya boleh punya 1 pengajuan yang masih berjalan
  active_member  CHAR(36) AS (IF(status IN ('draft','diajukan','diverifikasi','disetujui'), member_id, NULL)) VIRTUAL,
  CONSTRAINT fk_clr_member   FOREIGN KEY (member_id)   REFERENCES members(id) ON DELETE RESTRICT,
  CONSTRAINT fk_clr_thesis   FOREIGN KEY (thesis_id)   REFERENCES thesis_submissions(id),
  CONSTRAINT fk_clr_verifier FOREIGN KEY (verified_by) REFERENCES users(id),
  UNIQUE INDEX uq_clearance_active (active_member),
  INDEX idx_clearance_member (member_id),
  INDEX idx_clearance_status (status)
) ENGINE=InnoDB;

CREATE TABLE clearance_status_history (
  id           BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  request_id   CHAR(36) NOT NULL,
  from_status  VARCHAR(20),
  to_status    VARCHAR(20) NOT NULL,
  changed_by   CHAR(36),
  note         TEXT,
  changed_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_hist_req  FOREIGN KEY (request_id) REFERENCES clearance_requests(id) ON DELETE CASCADE,
  CONSTRAINT fk_hist_user FOREIGN KEY (changed_by) REFERENCES users(id),
  INDEX idx_clearance_history_req (request_id)
) ENGINE=InnoDB;

CREATE TABLE clearance_letters (
  id              CHAR(36) NOT NULL DEFAULT (UUID()) PRIMARY KEY,
  request_id      CHAR(36)    NOT NULL UNIQUE,
  letter_number   VARCHAR(60) NOT NULL UNIQUE,
  issued_at       DATE        NOT NULL DEFAULT (CURRENT_DATE),
  valid_until     DATE,
  signed_by       CHAR(36),
  verify_token    VARCHAR(64) NOT NULL UNIQUE DEFAULT (HEX(RANDOM_BYTES(24))),   -- untuk QR cek keaslian
  pdf_url         TEXT,
  is_revoked      TINYINT(1)  NOT NULL DEFAULT 0,
  revoked_reason  TEXT,
  created_at      TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_letter_req    FOREIGN KEY (request_id) REFERENCES clearance_requests(id) ON DELETE RESTRICT,
  CONSTRAINT fk_letter_signer FOREIGN KEY (signed_by)  REFERENCES users(id)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 9. NOTIFIKASI & AUDIT
-- ---------------------------------------------------------------------
CREATE TABLE notifications (
  id          CHAR(36) NOT NULL DEFAULT (UUID()) PRIMARY KEY,
  user_id     CHAR(36)     NOT NULL,
  title       VARCHAR(150) NOT NULL,
  body        TEXT,
  link        TEXT,
  is_read     TINYINT(1)   NOT NULL DEFAULT 0,
  created_at  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_notif_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  INDEX idx_notifications_user (user_id, is_read)
) ENGINE=InnoDB;

CREATE TABLE audit_logs (
  id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id     CHAR(36),
  action      VARCHAR(60) NOT NULL,
  entity      VARCHAR(60) NOT NULL,
  entity_id   VARCHAR(64),
  detail      JSON,
  ip_address  VARCHAR(45),
  created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_audit_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL,
  INDEX idx_audit_entity (entity, entity_id),
  INDEX idx_audit_user (user_id)
) ENGINE=InnoDB;

SET FOREIGN_KEY_CHECKS = 1;

-- ---------------------------------------------------------------------
-- 10. SEED MINIMAL
-- ---------------------------------------------------------------------
INSERT INTO categories (name, ddc_code) VALUES
  ('Karya Umum', '000'), ('Teknologi & Komputer', '004'),
  ('Ilmu Sosial', '300'), ('Sains', '500'), ('Teknik', '600'), ('Bahasa', '400');

-- ---------------------------------------------------------------------
-- 11. FUNCTION, PROCEDURE, TRIGGER  (butuh DELIMITER)
-- ---------------------------------------------------------------------
DELIMITER //

-- 11a. Cek kelayakan bebas pustaka -> 1 / 0
CREATE FUNCTION fn_is_eligible(p_member CHAR(36)) RETURNS TINYINT(1)
READS SQL DATA
BEGIN
  DECLARE v_need   TINYINT(1) DEFAULT 1;
  DECLARE v_loans  INT DEFAULT 0;
  DECLARE v_fines  DECIMAL(12,2) DEFAULT 0;
  DECLARE v_thesis INT DEFAULT 0;

  SELECT (setting_value = 'true') INTO v_need
    FROM settings WHERE setting_key = 'clearance_require_thesis';

  SELECT COUNT(*) INTO v_loans FROM loans
   WHERE member_id = p_member AND status = 'dipinjam';

  SELECT COALESCE(SUM(amount - paid_amount), 0) INTO v_fines FROM fines
   WHERE member_id = p_member AND status = 'belum_bayar';

  SELECT COUNT(*) INTO v_thesis FROM thesis_submissions
   WHERE member_id = p_member AND status = 'disetujui';

  RETURN (v_loans = 0 AND v_fines = 0 AND (v_need = 0 OR v_thesis > 0));
END//

-- 11b. Detail kelayakan (dipanggil backend: CALL sp_clearance_eligibility('<member_id>');)
CREATE PROCEDURE sp_clearance_eligibility(IN p_member CHAR(36))
READS SQL DATA
BEGIN
  SELECT
    (SELECT COUNT(*) FROM loans WHERE member_id = p_member AND status = 'dipinjam') AS active_loans,
    (SELECT COALESCE(SUM(amount - paid_amount), 0) FROM fines
       WHERE member_id = p_member AND status = 'belum_bayar')                       AS unpaid_fines,
    (SELECT COUNT(*) > 0 FROM thesis_submissions
       WHERE member_id = p_member AND status = 'disetujui')                         AS thesis_ok,
    fn_is_eligible(p_member)                                                        AS is_eligible;
END//

-- 11c. Validasi sebelum pinjam
CREATE TRIGGER trg_loans_before_insert BEFORE INSERT ON loans
FOR EACH ROW
BEGIN
  DECLARE v_status      VARCHAR(20);
  DECLARE v_max         SMALLINT;
  DECLARE v_active      INT;
  DECLARE v_unpaid      DECIMAL(12,2);
  DECLARE v_item_status VARCHAR(20);

  SELECT status, max_loans INTO v_status, v_max FROM members WHERE id = NEW.member_id;
  IF v_status <> 'aktif' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Anggota tidak aktif';
  END IF;

  SELECT COUNT(*) INTO v_active FROM loans WHERE member_id = NEW.member_id AND status = 'dipinjam';
  IF v_active >= v_max THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Batas pinjam tercapai';
  END IF;

  SELECT COALESCE(SUM(amount - paid_amount), 0) INTO v_unpaid FROM fines
   WHERE member_id = NEW.member_id AND status = 'belum_bayar';
  IF v_unpaid > 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Masih ada denda belum dibayar';
  END IF;

  SELECT status INTO v_item_status FROM book_items WHERE id = NEW.item_id;
  IF v_item_status NOT IN ('tersedia', 'dipesan') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Eksemplar tidak tersedia';
  END IF;
END//

-- 11d. Status eksemplar ikut berubah
CREATE TRIGGER trg_loans_after_insert AFTER INSERT ON loans
FOR EACH ROW
BEGIN
  UPDATE book_items SET status = 'dipinjam' WHERE id = NEW.item_id;
END//

CREATE TRIGGER trg_loans_after_update AFTER UPDATE ON loans
FOR EACH ROW
BEGIN
  IF OLD.status = 'dipinjam' AND NEW.status = 'dikembalikan' THEN
    UPDATE book_items SET status = 'tersedia' WHERE id = NEW.item_id AND status = 'dipinjam';
  ELSEIF OLD.status = 'dipinjam' AND NEW.status = 'hilang' THEN
    UPDATE book_items SET status = 'hilang' WHERE id = NEW.item_id;
  END IF;
END//

-- 11e. Denda otomatis saat kembali / hilang
CREATE TRIGGER trg_loans_before_update BEFORE UPDATE ON loans
FOR EACH ROW
BEGIN
  DECLARE v_per_day   DECIMAL(12,2);
  DECLARE v_cap_mult  DECIMAL(12,2);
  DECLARE v_lost_mult DECIMAL(12,2);
  DECLARE v_price     DECIMAL(12,2) DEFAULT 0;
  DECLARE v_late      INT;
  DECLARE v_amount    DECIMAL(12,2);

  SELECT CAST(setting_value AS DECIMAL(12,2)) INTO v_per_day   FROM settings WHERE setting_key = 'fine_per_day';
  SELECT CAST(setting_value AS DECIMAL(12,2)) INTO v_cap_mult  FROM settings WHERE setting_key = 'fine_max_multiplier';
  SELECT CAST(setting_value AS DECIMAL(12,2)) INTO v_lost_mult FROM settings WHERE setting_key = 'lost_fine_multiplier';

  IF OLD.status = 'dipinjam' AND NEW.status = 'dikembalikan' THEN
    SET NEW.return_date = COALESCE(NEW.return_date, CURRENT_DATE);
    SET v_late = GREATEST(DATEDIFF(NEW.return_date, NEW.due_date), 0);
    IF v_late > 0 THEN
      SELECT price INTO v_price FROM book_items WHERE id = NEW.item_id;
      SET v_amount = v_late * v_per_day;
      IF v_price > 0 THEN
        SET v_amount = LEAST(v_amount, v_price * v_cap_mult);   -- plafon denda
      END IF;
      INSERT INTO fines (member_id, loan_id, type, amount, reason)
      VALUES (NEW.member_id, NEW.id, 'terlambat', v_amount, CONCAT('Terlambat ', v_late, ' hari'));
    END IF;

  ELSEIF OLD.status = 'dipinjam' AND NEW.status = 'hilang' THEN
    SELECT price INTO v_price FROM book_items WHERE id = NEW.item_id;
    IF v_price > 0 THEN
      INSERT INTO fines (member_id, loan_id, type, amount, reason)
      VALUES (NEW.member_id, NEW.id, 'hilang', v_price * v_lost_mult, 'Buku dinyatakan hilang');
    END IF;
  END IF;
END//

-- 11f. Pembayaran denda
CREATE TRIGGER trg_fine_payments_before_insert BEFORE INSERT ON fine_payments
FOR EACH ROW
BEGIN
  DECLARE v_paid   DECIMAL(12,2);
  DECLARE v_amount DECIMAL(12,2);

  SELECT COALESCE(SUM(amount), 0) INTO v_paid FROM fine_payments WHERE fine_id = NEW.fine_id;
  SELECT amount INTO v_amount FROM fines WHERE id = NEW.fine_id;

  IF v_paid + NEW.amount > v_amount THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Total pembayaran melebihi nominal denda';
  END IF;
END//

CREATE TRIGGER trg_fine_payments_after_insert AFTER INSERT ON fine_payments
FOR EACH ROW
BEGIN
  DECLARE v_total  DECIMAL(12,2);
  DECLARE v_amount DECIMAL(12,2);

  SELECT COALESCE(SUM(amount), 0) INTO v_total FROM fine_payments WHERE fine_id = NEW.fine_id;
  SELECT amount INTO v_amount FROM fines WHERE id = NEW.fine_id;

  UPDATE fines
     SET paid_amount = v_total,
         status = IF(v_total >= v_amount, 'lunas', status)
   WHERE id = NEW.fine_id;
END//

-- 11g. Riwayat status pengajuan bebas pustaka
CREATE TRIGGER trg_clearance_after_insert AFTER INSERT ON clearance_requests
FOR EACH ROW
BEGIN
  INSERT INTO clearance_status_history (request_id, from_status, to_status, changed_by)
  VALUES (NEW.id, NULL, NEW.status, NEW.verified_by);
END//

CREATE TRIGGER trg_clearance_after_update AFTER UPDATE ON clearance_requests
FOR EACH ROW
BEGIN
  IF NOT (NEW.status <=> OLD.status) THEN
    INSERT INTO clearance_status_history (request_id, from_status, to_status, changed_by)
    VALUES (NEW.id, OLD.status, NEW.status, NEW.verified_by);
  END IF;
END//

-- 11h. Terbitkan surat: validasi ulang, buat nomor, nonaktifkan keanggotaan
--      CALL sp_issue_clearance_letter('<request_id>', '<signer_user_id>', @letter_id);
CREATE PROCEDURE sp_issue_clearance_letter(
  IN  p_request CHAR(36),
  IN  p_signer  CHAR(36),
  OUT p_letter  CHAR(36)
)
BEGIN
  DECLARE v_member CHAR(36);
  DECLARE v_status VARCHAR(20);
  DECLARE v_prefix VARCHAR(255);
  DECLARE v_valid  INT;
  DECLARE v_seq    BIGINT;
  DECLARE v_number VARCHAR(60);

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;

  START TRANSACTION;

  SELECT member_id, status INTO v_member, v_status
    FROM clearance_requests WHERE id = p_request FOR UPDATE;

  IF v_member IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Pengajuan tidak ditemukan';
  END IF;
  IF v_status <> 'disetujui' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Pengajuan belum disetujui';
  END IF;
  IF fn_is_eligible(v_member) = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Anggota belum memenuhi syarat bebas pustaka';
  END IF;

  SELECT setting_value INTO v_prefix FROM settings WHERE setting_key = 'clearance_letter_prefix';
  SELECT CAST(setting_value AS UNSIGNED) INTO v_valid FROM settings WHERE setting_key = 'clearance_validity_days';

  INSERT INTO clearance_letter_seq VALUES (NULL);
  SET v_seq = LAST_INSERT_ID();

  SET v_number = CONCAT(LPAD(v_seq, 4, '0'), '/', v_prefix, '/PERPUS/',
                        DATE_FORMAT(CURRENT_DATE, '%m'), '/', YEAR(CURRENT_DATE));
  SET p_letter = UUID();

  INSERT INTO clearance_letters (id, request_id, letter_number, valid_until, signed_by)
  VALUES (p_letter, p_request, v_number, DATE_ADD(CURRENT_DATE, INTERVAL v_valid DAY), p_signer);

  UPDATE clearance_requests SET status = 'diterbitkan', verified_by = p_signer WHERE id = p_request;
  UPDATE members SET status = 'alumni', deactivated_at = NOW() WHERE id = v_member;

  COMMIT;
END//

DELIMITER ;

-- ---------------------------------------------------------------------
-- 12. VIEW
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_active_loans AS
SELECT l.id, l.member_id, m.nim, u.full_name, b.title, bi.barcode,
       l.loan_date, l.due_date,
       GREATEST(DATEDIFF(CURRENT_DATE, l.due_date), 0) AS days_late,
       (CURRENT_DATE > l.due_date)                     AS is_overdue
FROM loans l
JOIN members    m  ON m.id  = l.member_id
JOIN users      u  ON u.id  = m.user_id
JOIN book_items bi ON bi.id = l.item_id
JOIN books      b  ON b.id  = bi.book_id
WHERE l.status = 'dipinjam';

CREATE OR REPLACE VIEW v_member_obligations AS
SELECT m.id AS member_id, m.nim, u.full_name,
       COALESCE(l.n, 0) AS active_loans,
       COALESCE(f.s, 0) AS unpaid_fines
FROM members m
JOIN users u ON u.id = m.user_id
LEFT JOIN (SELECT member_id, COUNT(*) AS n FROM loans WHERE status = 'dipinjam' GROUP BY member_id) l
       ON l.member_id = m.id
LEFT JOIN (SELECT member_id, SUM(amount - paid_amount) AS s FROM fines WHERE status = 'belum_bayar' GROUP BY member_id) f
       ON f.member_id = m.id;

CREATE OR REPLACE VIEW v_book_availability AS
SELECT b.id AS book_id, b.title, b.authors,
       COUNT(bi.id)                                              AS total_items,
       COALESCE(SUM(bi.status = 'tersedia'), 0)                  AS available_items
FROM books b
LEFT JOIN book_items bi ON bi.book_id = b.id AND bi.status <> 'dihapus'
GROUP BY b.id, b.title, b.authors;