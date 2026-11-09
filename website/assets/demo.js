const search = document.querySelector(".search input");
const conversations = [...document.querySelectorAll(".conversation")];
const chats = [...document.querySelectorAll(".chat")];
const empty = document.querySelector(".empty");

let selected = 0;

const buttons = conversations.map((row, index) => {
  const button = document.createElement("button");
  button.type = "button";
  button.className = row.className;
  button.append(...row.childNodes);
  button.addEventListener("click", () => show(index));
  row.replaceWith(button);
  return button;
});

function show(index) {
  selected = index;
  chats.forEach((chat, position) => {
    const active = position === selected;
    chat.hidden = !active;
    buttons[position].classList.toggle("active", active);
    buttons[position].setAttribute("aria-pressed", String(active));
  });
  empty.hidden = selected !== -1;
}

search.addEventListener("input", () => {
  const query = search.value.trim().toLowerCase();
  const matches = chats.map((chat) => chat.textContent.toLowerCase().includes(query));
  buttons.forEach((button, index) => {
    button.hidden = !matches[index];
  });
  show(matches[selected] ? selected : matches.indexOf(true));
});

show(0);
search.closest("label").hidden = false;
