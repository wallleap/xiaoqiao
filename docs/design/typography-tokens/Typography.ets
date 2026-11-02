// 开发参考，未接入entry；显式fp，避免将裸数当作vp字号。
export class Typography {
  static readonly Display_L: string = '56fp';
  static readonly Display_M: string = '48fp';
  static readonly Display_S: string = '38fp';
  static readonly Title_L: string = '30fp';
  static readonly Title_M: string = '24fp';
  static readonly Title_S: string = '20fp';
  static readonly Subtitle_L: string = '18fp';
  static readonly Subtitle_M: string = '16fp';
  static readonly Subtitle_S: string = '14fp';
  static readonly Body_L: string = '16fp';
  static readonly Body_M: string = '14fp';
  static readonly Body_S: string = '12fp';
  static readonly Caption_L: string = '12fp';
  static readonly Caption_M: string = '10fp';
  static readonly Number_Display: string = '38fp';
  static readonly Number_Input: string = '48fp';
  static readonly Number_Keypad: string = '30fp';
  // 默认Text不指定fontFamily；数字DIN只做设计标注，字库接入后再绑定。
}
