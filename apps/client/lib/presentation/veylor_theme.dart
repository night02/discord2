import 'package:flutter/material.dart';
class VeylorColors {
  static const rail=Color(0xFF1E1F22),navigation=Color(0xFF2B2D31),canvas=Color(0xFF313338);
  static const selected=Color(0xFF404249),composer=Color(0xFF383A40),text=Color(0xFFF2F3F5);
  static const muted=Color(0xFFB5BAC1),accent=Color(0xFF4BA9F4),success=Color(0xFF43B581),danger=Color(0xFFF26A73),divider=Color(0xFF24262A);
}
ThemeData veylorTheme()=>ThemeData.dark(useMaterial3:true).copyWith(
  scaffoldBackgroundColor:VeylorColors.canvas,
  colorScheme:const ColorScheme.dark(primary:VeylorColors.accent,surface:VeylorColors.navigation,onSurface:VeylorColors.text,error:VeylorColors.danger),
  dividerColor:VeylorColors.divider,
  tooltipTheme:const TooltipThemeData(waitDuration:Duration(milliseconds:400)),
  inputDecorationTheme:InputDecorationTheme(filled:true,fillColor:VeylorColors.rail,
    contentPadding:const EdgeInsets.symmetric(horizontal:16,vertical:15),
    border:OutlineInputBorder(borderRadius:BorderRadius.circular(8),borderSide:BorderSide.none),
    focusedBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(8),borderSide:const BorderSide(color:VeylorColors.accent)),
    hintStyle:const TextStyle(color:VeylorColors.muted,fontSize:14)),
  filledButtonTheme:FilledButtonThemeData(style:FilledButton.styleFrom(foregroundColor:const Color(0xFF071C2D),
    textStyle:const TextStyle(fontWeight:FontWeight.w700),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(8)),
    padding:const EdgeInsets.symmetric(horizontal:20,vertical:16))),
  iconButtonTheme:IconButtonThemeData(style:IconButton.styleFrom(foregroundColor:VeylorColors.muted,minimumSize:const Size(36,36),padding:const EdgeInsets.all(8))),
  snackBarTheme:const SnackBarThemeData(behavior:SnackBarBehavior.floating));
class BrandMark extends StatelessWidget {
  const BrandMark({super.key,this.size=48});final double size;
  @override Widget build(BuildContext context)=>ClipRRect(borderRadius:BorderRadius.circular(size*.26),
    child:Image.asset('assets/veylor_logo.png',width:size,height:size,fit:BoxFit.cover,filterQuality:FilterQuality.medium));
}
class InitialAvatar extends StatelessWidget {
  const InitialAvatar({super.key,required this.name,this.radius=19});final String name;final double radius;
  @override Widget build(BuildContext context){
    const colors=[Color(0xFF5865F2),Color(0xFF387C9F),Color(0xFF7B59A9),Color(0xFF3A806D)];
    final hash=name.runes.fold<int>(0,(a,b)=>a+b);
    return CircleAvatar(radius:radius,backgroundColor:colors[hash%colors.length],
      child:Text(name.isEmpty?'?':name.characters.first.toUpperCase(),style:TextStyle(color:Colors.white,fontSize:radius*.78,fontWeight:FontWeight.w700)));
  }
}
class ErrorNotice extends StatelessWidget {
  const ErrorNotice({super.key,required this.message,required this.onDismiss});final String message;final VoidCallback onDismiss;
  @override Widget build(BuildContext context)=>Container(width:double.infinity,color:const Color(0xFF453136),padding:const EdgeInsets.fromLTRB(12,5,5,5),
    child:Row(children:[const Icon(Icons.info_outline,color:VeylorColors.danger,size:18),const SizedBox(width:10),
      Expanded(child:Text(message,style:const TextStyle(fontSize:12,color:VeylorColors.text))),
      IconButton(tooltip:'Fechar aviso',onPressed:onDismiss,icon:const Icon(Icons.close,size:17))]));
}
