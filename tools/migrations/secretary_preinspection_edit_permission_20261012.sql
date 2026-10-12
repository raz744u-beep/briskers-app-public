-- Office/secretary can start and edit job pre-inspections.
-- Assigned mechanic permissions remain unchanged.
INSERT INTO briskers.role_permissions (role_code, permission_code)
VALUES ('office', 'inspections.edit')
ON CONFLICT DO NOTHING;
