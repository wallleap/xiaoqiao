import { Driver, ON } from '@kit.TestKit';

export async function enterAmount(driver: Driver, fieldId: string, value: string): Promise<void> {
  const input = await driver.waitForComponent(ON.id(fieldId), 5000);
  if (input === null) { throw new Error('MISSING_AMOUNT_INPUT_' + fieldId); }
  await input.click();
  const clear = await driver.waitForComponent(ON.id(fieldId + '-key-清空'), 5000);
  if (clear === null) { throw new Error('MISSING_AMOUNT_KEYBOARD_' + fieldId); }
  await clear.click();
  for (const digit of value) {
    await (await driver.findComponent(ON.id(fieldId + '-key-' + digit))).click();
  }
}

export async function hideAmountKeyboard(driver: Driver, fieldId: string): Promise<void> {
  await (await driver.findComponent(ON.id(fieldId + '-hide-keyboard'))).click();
  for (let attempt = 0; attempt < 20; attempt++) {
    if (await driver.findComponent(ON.id(fieldId + '-native-keyboard')) === null) { return; }
    await driver.delayMs(50);
  }
  throw new Error('AMOUNT_KEYBOARD_STILL_VISIBLE_' + fieldId);
}
