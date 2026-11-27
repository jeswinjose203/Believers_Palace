CREATE TABLE catechism_materials (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    class_id UUID NOT NULL REFERENCES catechism_classes(id) ON DELETE CASCADE,
    author_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    kind TEXT NOT NULL CHECK (kind IN ('note', 'video')),
    title TEXT NOT NULL CHECK (length(title) BETWEEN 1 AND 200),
    description TEXT NOT NULL DEFAULT '',
    storage_key TEXT,
    file_name TEXT,
    mime_type TEXT,
    external_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT catechism_materials_source_check CHECK (
        (kind = 'note' AND storage_key IS NOT NULL AND file_name IS NOT NULL
            AND mime_type = 'application/pdf' AND external_url IS NULL)
        OR
        (kind = 'video' AND storage_key IS NULL AND file_name IS NULL
            AND mime_type IS NULL AND external_url IS NOT NULL)
    )
);

CREATE INDEX catechism_materials_class ON catechism_materials(class_id, created_at DESC, id DESC);
