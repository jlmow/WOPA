import type { FocusEvent, PointerEvent } from "react";

// No Android, dar focus() por código a um <input> costuma abrir o
// teclado nativo -- mau nos ecrãs de leitura, onde o foco é posto
// programaticamente (useEffect) para o leitor físico (keyboard wedge)
// escrever sem o operador ter de tocar no ecrã. `inputmode="none"`
// evita isso, mas bloquearia também o teclado quando o operador quer
// mesmo escrever à mão -- por isso o campo começa em "none" e só passa
// a "text" no toque real (onPointerDown, que dispara antes do focus
// nativo, logo já em tempo de mudar o atributo antes de o browser
// decidir mostrar o teclado), voltando a "none" ao sair do campo
// (onBlur), pronto para o próximo focus programático.
export function allowKeyboardOnTap(e: PointerEvent<HTMLInputElement>) {
  e.currentTarget.setAttribute("inputmode", "text");
}

export function suppressKeyboardOnBlur(e: FocusEvent<HTMLInputElement>) {
  e.currentTarget.setAttribute("inputmode", "none");
}
