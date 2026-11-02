import { LayoutToken } from './LayoutToken';

// 应用语义别名；布局数值单位vp。未接入业务代码。
export class LayoutSemantic {
  static readonly radius_tag: number = LayoutToken.corner_radius_level2;
  static readonly radius_media: number = LayoutToken.corner_radius_level4;
  static readonly radius_input: number = LayoutToken.corner_radius_level6;
  static readonly radius_keypad: number = LayoutToken.corner_radius_level6;
  static readonly radius_card: number = LayoutToken.corner_radius_level8;
  static readonly radius_summary: number = LayoutToken.corner_radius_level10;
  static readonly radius_button: number = LayoutToken.corner_radius_level10;
  static readonly radius_menu: number = LayoutToken.corner_radius_level10;
  static readonly radius_sheet: number = LayoutToken.corner_radius_level16;
  static readonly radius_dialog: number = LayoutToken.corner_radius_level16;
  static readonly gap_text_vertical: number = LayoutToken.Padding_level1;
  static readonly gap_inline: number = LayoutToken.Padding_level4;
  static readonly gap_keypad: number = LayoutToken.Padding_level4;
  static readonly gap_card: number = LayoutToken.Padding_level6;
  static readonly gap_control: number = LayoutToken.Padding_level4;
  static readonly gap_control_large: number = LayoutToken.Padding_level8;
  static readonly gap_section: number = LayoutToken.Padding_level12;
  static readonly padding_card: number = LayoutToken.Padding_level8;
  static readonly padding_dialog: number = LayoutToken.Padding_level12;
  static readonly gap_columns: number = LayoutToken.Padding_level12;
  static readonly margin_phone_horizontal: number = 16;
  static readonly margin_phone_top: number = 36;
  static readonly margin_phone_bottom: number = 28;
  static readonly margin_foldable_horizontal: number = 24;
  static readonly margin_foldable_top: number = 36;
  static readonly margin_foldable_bottom: number = 28;
  static readonly margin_tablet_horizontal: number = 32;
  static readonly margin_tablet_top: number = 36;
  static readonly margin_tablet_bottom: number = 28;
  static readonly margin_tv_horizontal: number = 48;
  static readonly margin_tv_top: number = 27;
  static readonly margin_tv_bottom: number = 27;
  static readonly margin_watch_horizontal: number = 26;
  static readonly margin_watch_top: number = 20;
  static readonly margin_watch_bottom: number = 20;
  static readonly margin_pc_horizontal: number = 40;
  static readonly margin_cockpit_horizontal: number = 48;
}
