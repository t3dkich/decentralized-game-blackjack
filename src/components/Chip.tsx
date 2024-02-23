import React from 'react';
import "../assets/blackChip.png"

//mapping of chip values to images
type ChipProps = {
  value: number;
  onClick: () => void;
};

const getChipImage = (value: number): string => {
  switch(value) {
    case 1:
    case 5:
    case 10:
    case 25:
    case 100:
      return "../assets/blackChip.png";
    default:
      return '../assets/blackChip.png'; // default or fallback image
  }
};

// Usage


const Chip: React.FC<ChipProps> = ({ value, onClick }) => {
  const ChipImage = getChipImage(value);
  return (
    <div className="chip" onClick={onClick} style={{backgroundImage: `url(${ChipImage})`}}>
      ${value}
    </div>
  );
};

export default Chip;
