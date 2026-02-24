import { useState } from 'react';
import PhotoImage from './PhotoImage';
import './ImageGrid.css';

function ImageGrid({ images, onImageClick, onDeleteImage }) {
  const [menuOpen, setMenuOpen] = useState(null);

  const handleMenuToggle = (e, imageId) => {
    e.stopPropagation();
    setMenuOpen(menuOpen === imageId ? null : imageId);
  };

  const handleDelete = (e, imageId) => {
    e.stopPropagation();
    setMenuOpen(null);
    if (onDeleteImage) {
      onDeleteImage(imageId);
    }
  };

  const handleClickOutside = () => {
    setMenuOpen(null);
  };

  return (
    <div className="image-grid" onClick={handleClickOutside}>
      {images.map((image, index) => (
        <div 
          key={image.id} 
          className={`image-item fade-in stagger-${(index % 6) + 1}`}
        >
          <div 
            className="image-card"
            onClick={() => onImageClick(image)}
          >
            <div className="image-wrapper">
              <PhotoImage
                url={image.url}
                alt={image.name}
                loading="lazy"
              />
            </div>
          </div>
          
          {onDeleteImage && (
            <div className="image-menu-container">
              <button 
                className="image-menu-btn"
                onClick={(e) => handleMenuToggle(e, image.id)}
                aria-label="메뉴 열기"
              >
                <span className="menu-dot"></span>
                <span className="menu-dot"></span>
                <span className="menu-dot"></span>
              </button>
              
              {menuOpen === image.id && (
                <div className="image-menu scale-in">
                  <button 
                    className="menu-item danger"
                    onClick={(e) => handleDelete(e, image.id)}
                  >
                    <span className="menu-icon">🗑</span>
                    사진 삭제
                  </button>
                </div>
              )}
            </div>
          )}
        </div>
      ))}
    </div>
  );
}

export default ImageGrid;
