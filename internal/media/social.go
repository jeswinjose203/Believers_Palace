package media

import (
	"bufio"
	"io"
	"net/http"
)

const SocialMaxBytes = 25 << 20

func (s *Service) UploadSocial(content io.Reader) (*UploadResult, error) {
	reader := bufio.NewReaderSize(content, 512)
	header, _ := reader.Peek(512)
	mime := http.DetectContentType(header)
	ext := allowedImageTypes[mime]
	switch mime {
	case "video/mp4":
		ext = ".mp4"
	case "video/webm":
		ext = ".webm"
	}
	if ext == "" {
		return nil, ErrUnsupportedType
	}
	key := randomKey() + ext
	size, err := s.storage.Save(key, io.LimitReader(reader, SocialMaxBytes+1))
	if err != nil {
		return nil, err
	}
	if size > SocialMaxBytes {
		s.Remove(key)
		return nil, ErrTooLarge
	}
	return &UploadResult{URL: s.publicURL(key), FileName: key, MimeType: mime, FileSize: size}, nil
}

func (s *Service) Remove(key string) {
	_ = s.storage.Remove(key)
}
