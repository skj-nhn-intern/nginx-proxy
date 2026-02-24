import { useEffect } from 'react';
import PhotoImage from './PhotoImage';
import './ImageModal.css';

function ImageModal({ image, onClose }) {
  useEffect(() => {
    const handleEscape = (e) => {
      if (e.key === 'Escape') {
        onClose();
      }
    };
    
    document.addEventListener('keydown', handleEscape);
    document.body.style.overflow = 'hidden';
    
    return () => {
      document.removeEventListener('keydown', handleEscape);
      document.body.style.overflow = '';
    };
  }, [onClose]);

  const handleBackdropClick = (e) => {
    if (e.target === e.currentTarget) {
      onClose();
    }
  };

  return (
    <div className="image-modal-overlay" onClick={handleBackdropClick}>
      <div className="image-modal scale-in">
        <button className="modal-close-btn" onClick={onClose}>
          ✕
        </button>
        
        <div className="modal-content">
          <div className="modal-image-container">
            <PhotoImage url={image.url} alt={image.name} />
          </div>
          
          <div className="modal-info">
            <h2 className="image-name">{image.name}</h2>
            {image.description && (
              <p className="image-description">{image.description}</p>
            )}
            <div className="image-meta">
              <span className="meta-item">
                <span className="meta-icon">📅</span>
                {image.createdAt}
              </span>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

export default ImageModal;
