-- ============================================================
-- PATHFINDER PORTAL — images pasted into notifications
--
-- Admins wanted to paste a screenshot straight into a message
-- rather than saving a file and sharing a link.
--
-- ⚠ THE BUCKET IS PUBLIC, AND IT HAS TO BE.
--
-- Email clients fetch images over plain HTTP with no session, so
-- an authenticated URL cannot work. The filenames are random and
-- effectively unguessable, but anyone who has a URL can open the
-- image indefinitely — including after the email is deleted.
--
-- Fine for a concert flyer or a map. Not fine for a screenshot
-- of the schedule showing other students' names, or anything with
-- payment details. The composer warns about this at the point of
-- pasting.
--
-- ⚠ Run ONE STATEMENT AT A TIME and check each result.
-- ============================================================


-- ------------------------------------------------------------
-- 1. The bucket
--
-- 5 MB is generous for a screenshot and small enough to stop
-- someone pasting a photo straight off a phone.
-- ------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'notification-images', 'notification-images', true, 5242880,
  ARRAY['image/png','image/jpeg','image/gif','image/webp']
)
ON CONFLICT (id) DO UPDATE
  SET public             = true,
      file_size_limit    = 5242880,
      allowed_mime_types = ARRAY['image/png','image/jpeg','image/gif','image/webp'];


-- ------------------------------------------------------------
-- 2. Who may upload
--
-- Admins and the super user only. Teachers and students have no
-- reason to put images here, and every extra writer is another
-- way for something sensitive to end up on a public URL.
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "admins upload notification images" ON storage.objects;
CREATE POLICY "admins upload notification images"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'notification-images'
    AND get_my_role() IN ('superuser','admin')
  );

DROP POLICY IF EXISTS "admins manage notification images" ON storage.objects;
CREATE POLICY "admins manage notification images"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'notification-images'
    AND get_my_role() IN ('superuser','admin')
  );

-- Reading is public by virtue of the bucket, which is what lets an
-- email client display the image. No SELECT policy is needed.


-- ============================================================
-- VERIFY
-- ============================================================
SELECT id, public, file_size_limit, allowed_mime_types
  FROM storage.buckets
 WHERE id = 'notification-images';

SELECT policyname, cmd
  FROM pg_policies
 WHERE tablename = 'objects' AND schemaname = 'storage'
   AND policyname LIKE '%notification images%'
 ORDER BY policyname;


-- ============================================================
-- HOUSEKEEPING
--
-- Nothing removes these images. They accumulate, and each one
-- stays reachable for ever. Worth reviewing occasionally:
--
--   SELECT name, created_at,
--          round((metadata->>'size')::numeric / 1024) AS kb
--     FROM storage.objects
--    WHERE bucket_id = 'notification-images'
--    ORDER BY created_at DESC;
--
-- And deleting anything old enough that the email has served its
-- purpose:
--
--   DELETE FROM storage.objects
--    WHERE bucket_id = 'notification-images'
--      AND created_at < now() - interval '1 year';
-- ============================================================
