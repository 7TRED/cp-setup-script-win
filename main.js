// Basic setup
console.log("main.js loaded");

// Initialize chess.js
const chess = new Chess();
console.log(chess.ascii());

// Pokémon sprite mapping
const pokemonSpriteMapping = {
    'p': { name: 'Pikachu', url: 'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/25.png' },
    'r': { name: 'Snorlax', url: 'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/143.png' },
    'n': { name: 'Rapidash', url: 'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/78.png' },
    'b': { name: 'Alakazam', url: 'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/65.png' },
    'q': { name: 'Nidoqueen', url: 'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/31.png' },
    'k': { name: 'Nidoking', url: 'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/34.png' },
};

const shinyPokemonSpriteMapping = {
    'p': { name: 'Pikachu', url: 'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/shiny/25.png' },
    'r': { name: 'Snorlax', url: 'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/shiny/143.png' },
    'n': { name: 'Rapidash', url: 'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/shiny/78.png' },
    'b': { name: 'Alakazam', url: 'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/shiny/65.png' },
    'q': { name: 'Nidoqueen', url: 'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/shiny/31.png' },
    'k': { name: 'Nidoking', url: 'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/shiny/34.png' },
};

// UI Elements
const turnInfo = document.getElementById('turn-info');
const statusInfo = document.getElementById('status-info');
const newGameBtn = document.getElementById('new-game-btn');

newGameBtn.addEventListener('click', () => {
    chess.reset();
    updateBoard();
    updateUI();
});

function updateUI() {
    const turn = chess.turn() === 'w' ? 'White' : 'Black';
    turnInfo.textContent = `Turn: ${turn}`;

    let status = '';
    if (chess.in_checkmate()) {
        status = `Checkmate! ${turn === 'White' ? 'Black' : 'White'} wins.`;
    } else if (chess.in_check()) {
        status = 'Check!';
    } else if (chess.in_draw()) {
        status = 'Draw.';
    } else if (chess.in_stalemate()) {
        status = 'Stalemate.';
    } else if (chess.in_threefold_repetition()) {
        status = 'Draw by threefold repetition.';
    } else if (chess.insufficient_material()) {
        status = 'Draw by insufficient material.';
    }
    statusInfo.textContent = status;
}

// Create the scene
const scene = new THREE.Scene();
scene.background = new THREE.Color(0xcccccc);

// Create the camera
const camera = new THREE.PerspectiveCamera(75, window.innerWidth / window.innerHeight, 0.1, 1000);
camera.position.z = 10;
camera.position.y = 10;
camera.lookAt(0, 0, 0);

// Create the renderer
const renderer = new THREE.WebGLRenderer();
renderer.setSize(window.innerWidth, window.innerHeight);
document.body.appendChild(renderer.domElement);

// Add OrbitControls
const controls = new THREE.OrbitControls(camera, renderer.domElement);
controls.target.set(0, 0, 0);
controls.enableDamping = true;

// Add lighting
const ambientLight = new THREE.AmbientLight(0xffffff, 0.5);
scene.add(ambientLight);

const directionalLight = new THREE.DirectionalLight(0xffffff, 0.5);
directionalLight.position.set(0, 1, 1);
scene.add(directionalLight);

// Create the chessboard
const boardGroup = new THREE.Group();
const tileSize = 1;
const boardSize = 8;
const boardGeometry = new THREE.PlaneGeometry(tileSize, tileSize);

for (let i = 0; i < boardSize; i++) {
    for (let j = 0; j < boardSize; j++) {
        const isWhite = (i + j) % 2 === 0;
        const color = isWhite ? 0xebebd3 : 0x769656;
        const boardMaterial = new THREE.MeshStandardMaterial({ color: color });
        const tile = new THREE.Mesh(boardGeometry, boardMaterial);
        tile.position.set(i - boardSize / 2 + 0.5, 0, j - boardSize / 2 + 0.5);
        tile.rotation.x = -Math.PI / 2;
        boardGroup.add(tile);
    }
}
scene.add(boardGroup);

// Create Pokémon chess pieces
const textureLoader = new THREE.TextureLoader();
const piecesGroup = new THREE.Group();
scene.add(piecesGroup);

function updateBoard() {
    // Remove all pieces from the scene
    while (piecesGroup.children.length) {
        piecesGroup.remove(piecesGroup.children[0]);
    }

    const board = chess.board();
    for (let rank = 0; rank < board.length; rank++) {
        const row = board[rank];
        for (let file = 0; file < row.length; file++) {
            const piece = row[file];
            if (piece) {
                const mapping = piece.color === 'w' ? pokemonSpriteMapping : shinyPokemonSpriteMapping;
                const spriteUrl = mapping[piece.type].url;

                const texture = textureLoader.load(spriteUrl);
                const material = new THREE.SpriteMaterial({ map: texture, color: 0xffffff });
                const sprite = new THREE.Sprite(material);

                // Position the sprite
                const x = file - boardSize / 2 + 0.5;
                const z = (7 - rank) - boardSize / 2 + 0.5;
                sprite.position.set(x, 0.5, z);

                // Store chess square info in the object
                const square = String.fromCharCode('a'.charCodeAt(0) + file) + (8 - rank);
                sprite.userData.square = square;

                piecesGroup.add(sprite);
            }
        }
    }
}

updateBoard();
updateUI();

const raycaster = new THREE.Raycaster();
const mouse = new THREE.Vector2();
let selectedPiece = null;

function selectPiece(piece) {
    piece.material.color.set(0xbbffbb);
}

function deselectPiece(piece) {
    if (piece) {
        piece.material.color.set(0xffffff);
    }
}

function positionToSquare(position) {
    const fileIndex = Math.round(position.x + boardSize / 2 - 0.5);
    const rankIndex = Math.round(position.z + boardSize / 2 - 0.5);
    if (fileIndex < 0 || fileIndex > 7 || rankIndex < 0 || rankIndex > 7) return null;
    const file = String.fromCharCode('a'.charCodeAt(0) + fileIndex);
    const rank = (rankIndex + 1).toString();
    return file + rank;
}

function onMouseClick(event) {
    mouse.x = (event.clientX / window.innerWidth) * 2 - 1;
    mouse.y = - (event.clientY / window.innerHeight) * 2 + 1;
    raycaster.setFromCamera(mouse, camera);

    if (selectedPiece) {
        const boardIntersects = raycaster.intersectObjects(boardGroup.children);
        if (boardIntersects.length > 0) {
            const clickedTile = boardIntersects[0].object;
            const toSquare = positionToSquare(clickedTile.position);

            if (toSquare) {
                const fromSquare = selectedPiece.userData.square;
                const move = chess.move({ from: fromSquare, to: toSquare, promotion: 'q' });

                if (move) {
                    updateBoard();
                    updateUI();
                    console.log(chess.ascii());
                }
            }
        }
        deselectPiece(selectedPiece);
        selectedPiece = null;
    } else {
        const intersects = raycaster.intersectObjects(piecesGroup.children);
        if (intersects.length > 0) {
            const clickedObject = intersects[0].object;
            const square = clickedObject.userData.square;
            const pieceOnSquare = chess.get(square);
            if (pieceOnSquare && pieceOnSquare.color === chess.turn()) {
                deselectPiece(selectedPiece);
                selectedPiece = clickedObject;
                selectPiece(selectedPiece);
            }
        }
    }
}

window.addEventListener('click', onMouseClick, false);

// Render loop
function animate() {
    requestAnimationFrame(animate);
    controls.update();
    renderer.render(scene, camera);
}

animate();
